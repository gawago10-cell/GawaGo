import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { getConversations, getMessages, markConversationRead, sendMessage } from "../services/backendDataService";

const MESSAGE_POLL_MS = 4000;
const CONVERSATION_POLL_MS = 30000;
const MAX_MESSAGE_LENGTH = 2000;
const CHAT_ROLES = new Set(["household", "worker"]);

function getInitials(name) {
  return String(name || "U")
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() || "")
    .join("");
}

function formatTimestamp(value) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) return "";
  return date.toLocaleString("en-PH", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
}

function lastSentId(messages = []) {
  return messages.reduce((max, message) => (message.status === "sent" && message.id > max ? message.id : max), 0) || null;
}

// Server messages keyed by id (so a poll and a POST response that return the
// same message never duplicate it), followed by local sending/failed ones.
function mergeMessages(existing = [], incoming = []) {
  const byId = new Map();
  const local = [];
  existing.forEach((message) => (message.status === "sent" ? byId.set(message.id, message) : local.push(message)));
  incoming.forEach((message) => byId.set(message.id, message));
  return [...[...byId.values()].sort((a, b) => a.id - b.id), ...local];
}

function Avatar({ name, photo }) {
  return photo ? <img src={photo} alt={name} /> : <span>{getInitials(name)}</span>;
}

export default function ChatWidget({ currentUser }) {
  const role = currentUser?.role;
  const enabled = CHAT_ROLES.has(role);
  const [collapsed, setCollapsed] = useState(true);
  const [conversations, setConversations] = useState([]);
  const [conversationsLoaded, setConversationsLoaded] = useState(false);
  const [activeId, setActiveId] = useState(null);
  const [messagesById, setMessagesById] = useState({});
  const [draft, setDraft] = useState("");
  const [loadError, setLoadError] = useState("");
  const messagesRef = useRef(messagesById);
  const messageBodyRef = useRef(null);
  messagesRef.current = messagesById;

  const activeConversation = conversations.find((conversation) => conversation.id === activeId) || null;
  const activeMessages = activeId ? messagesById[activeId] : undefined;
  const unreadTotal = useMemo(
    () => conversations.reduce((total, conversation) => total + (conversation.unreadCount || 0), 0),
    [conversations],
  );

  const refreshConversations = useCallback(async () => {
    try {
      const next = await getConversations();
      setConversations(next);
      setConversationsLoaded(true);
      setActiveId((current) => (next.some((conversation) => conversation.id === current) ? current : next[0]?.id ?? null));
    } catch {
      setConversationsLoaded(true);
    }
  }, []);

  // Start clean for whoever is logged in; a previous user's threads must not linger.
  useEffect(() => {
    setConversations([]);
    setConversationsLoaded(false);
    setActiveId(null);
    setMessagesById({});
    setDraft("");
    setCollapsed(true);
    if (!enabled) return undefined;
    refreshConversations();
    const intervalId = window.setInterval(refreshConversations, CONVERSATION_POLL_MS);
    return () => window.clearInterval(intervalId);
  }, [enabled, currentUser?.username, refreshConversations]);

  useEffect(() => {
    if (!collapsed && enabled) refreshConversations();
  }, [collapsed, enabled, refreshConversations]);

  // Load history, then poll with ?after= while a thread is open.
  useEffect(() => {
    if (collapsed || !activeId) return undefined;
    let cancelled = false;
    let inFlight = false;
    const conversationId = activeId;
    const tick = async () => {
      if (inFlight) return;
      inFlight = true;
      try {
        const incoming = await getMessages(conversationId, lastSentId(messagesRef.current[conversationId]));
        if (cancelled) return;
        setLoadError("");
        setMessagesById((prev) => ({ ...prev, [conversationId]: mergeMessages(prev[conversationId], incoming) }));
        if (incoming.some((message) => !message.isMine && !message.isRead)) {
          markConversationRead(conversationId).catch(() => {});
        }
        setConversations((prev) =>
          prev.map((conversation) =>
            conversation.id === conversationId
              ? {
                  ...conversation,
                  unreadCount: 0,
                  lastMessage: incoming[incoming.length - 1] || conversation.lastMessage,
                }
              : conversation,
          ),
        );
      } catch (error) {
        if (cancelled) return;
        if (error.status === 403) {
          refreshConversations();
        } else {
          setLoadError("Can't reach the server. Retrying…");
        }
      } finally {
        inFlight = false;
      }
    };
    tick();
    const intervalId = window.setInterval(tick, MESSAGE_POLL_MS);
    return () => {
      cancelled = true;
      window.clearInterval(intervalId);
    };
  }, [collapsed, activeId, refreshConversations]);

  useEffect(() => {
    if (!collapsed && messageBodyRef.current) {
      messageBodyRef.current.scrollTop = messageBodyRef.current.scrollHeight;
    }
  }, [collapsed, activeId, activeMessages?.length]);

  const deliver = useCallback(async (conversationId, clientId, content) => {
    const setLocal = (updater) =>
      setMessagesById((prev) => ({ ...prev, [conversationId]: updater(prev[conversationId] || []) }));
    setLocal((list) => list.map((message) => (message.clientId === clientId ? { ...message, status: "sending", error: "" } : message)));
    try {
      const saved = await sendMessage(conversationId, content);
      setLocal((list) => mergeMessages(list.filter((message) => message.clientId !== clientId), [saved]));
      setConversations((prev) =>
        prev.map((conversation) => (conversation.id === conversationId ? { ...conversation, lastMessage: saved } : conversation)),
      );
    } catch (error) {
      setLocal((list) =>
        list.map((message) =>
          message.clientId === clientId ? { ...message, status: "failed", error: error.message || "Message not sent." } : message,
        ),
      );
      if (error.status === 403) refreshConversations();
    }
  }, [refreshConversations]);

  const submitMessage = () => {
    const content = draft.trim();
    if (!activeConversation || !content) return;
    const clientId = `local-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    setMessagesById((prev) => ({
      ...prev,
      [activeConversation.id]: [
        ...(prev[activeConversation.id] || []),
        { id: clientId, clientId, content, isMine: true, createdAt: new Date().toISOString(), status: "sending", senderName: "You" },
      ],
    }));
    setDraft("");
    deliver(activeConversation.id, clientId, content);
  };

  if (!enabled) return null;

  if (collapsed) {
    return (
      <div className="gawago-chat-dock gawago-chat-dock-collapsed" aria-label="Household and worker chat">
        <button
          type="button"
          className="gawago-chat-fab"
          aria-label={unreadTotal > 0 ? `Open chat, ${unreadTotal} unread message${unreadTotal > 1 ? "s" : ""}` : "Open chat"}
          onClick={() => setCollapsed(false)}
        >
          <span className="material-symbols-outlined" aria-hidden="true">chat</span>
          {unreadTotal > 0 ? <span className="gawago-chat-fab-badge">{unreadTotal > 9 ? "9+" : unreadTotal}</span> : null}
        </button>
      </div>
    );
  }

  const emptyText =
    role === "household"
      ? "Chat becomes available once you hire a worker."
      : "Chat becomes available once you get hired.";

  return (
    <div className="gawago-chat-dock" aria-label="Household and worker chat">
      <section className="gawago-chat-panel">
        <header className="gawago-chat-panel-head">
          <div className="gawago-chat-panel-identity">
            {activeConversation ? (
              <div className="gawago-chat-profile-trigger">
                <Avatar name={activeConversation.otherPartyName} photo={activeConversation.otherPartyPhoto} />
              </div>
            ) : null}
            <div className="gawago-chat-panel-title">
              <strong>{activeConversation?.otherPartyName || "Messages"}</strong>
              <span>{activeConversation ? `${activeConversation.jobTitle} • ${activeConversation.statusLabel}` : "No active hires"}</span>
            </div>
          </div>
          <button type="button" className="gawago-chat-toggle" aria-label="Collapse chat" onClick={() => setCollapsed(true)}>
            -
          </button>
        </header>

        {!conversations.length ? (
          <div className="gawago-chat-empty">
            <span className="material-symbols-outlined" aria-hidden="true">forum</span>
            <p>{conversationsLoaded ? emptyText : "Loading conversations…"}</p>
          </div>
        ) : (
          <div className="gawago-chat-panel-body">
            <aside className="gawago-chat-conversation-list">
              {conversations.map((conversation) => (
                <button
                  key={conversation.id}
                  type="button"
                  className={`gawago-chat-conversation-item ${conversation.id === activeId ? "active" : ""}`}
                  onClick={() => setActiveId(conversation.id)}
                >
                  <div className="gawago-chat-conversation-avatar">
                    <Avatar name={conversation.otherPartyName} photo={conversation.otherPartyPhoto} />
                  </div>
                  <div className="gawago-chat-conversation-copy">
                    <strong>
                      {conversation.otherPartyName}
                      {conversation.unreadCount > 0 && conversation.id !== activeId ? (
                        <span className="gawago-chat-unread-dot">{conversation.unreadCount}</span>
                      ) : null}
                    </strong>
                    <span>{conversation.lastMessage?.content || conversation.jobTitle}</span>
                  </div>
                </button>
              ))}
            </aside>

            <div className="gawago-chat-thread">
              <div className="gawago-chat-thread-meta">
                <strong>{activeConversation?.otherPartyName}</strong>
                <span>{activeConversation?.jobTitle}</span>
              </div>

              <div className="gawago-chat-messages" ref={messageBodyRef} aria-live="polite">
                {activeMessages === undefined ? (
                  <p className="gawago-chat-thread-note">Loading messages…</p>
                ) : activeMessages.length === 0 ? (
                  <p className="gawago-chat-thread-note">No messages yet. Say hello to coordinate the job.</p>
                ) : (
                  activeMessages.map((message) => (
                    <article
                      key={message.clientId || message.id}
                      className={`gawago-chat-bubble ${message.isMine ? "outgoing" : "incoming"} ${message.status !== "sent" ? message.status : ""}`}
                    >
                      <p>{message.content}</p>
                      <div className="gawago-chat-bubble-meta">
                        <span>{message.isMine ? "You" : message.senderName}</span>
                        <span>
                          {message.status === "sending"
                            ? "Sending…"
                            : message.status === "failed"
                              ? "Not sent"
                              : formatTimestamp(message.createdAt)}
                        </span>
                      </div>
                      {message.status === "failed" ? (
                        <div className="gawago-chat-failed">
                          <span>{message.error}</span>
                          <button type="button" onClick={() => deliver(activeId, message.clientId, message.content)}>
                            Retry
                          </button>
                        </div>
                      ) : null}
                    </article>
                  ))
                )}
              </div>

              <div className="gawago-chat-composer">
                {loadError ? <p className="gawago-chat-load-error">{loadError}</p> : null}
                <div className="gawago-chat-composer-row gawago-chat-composer-row-text">
                  <input
                    id="gawago-chat-draft"
                    type="text"
                    value={draft}
                    maxLength={MAX_MESSAGE_LENGTH}
                    placeholder={activeConversation ? `Message ${activeConversation.otherPartyName}...` : "Type a message..."}
                    onChange={(event) => setDraft(event.target.value)}
                    onKeyDown={(event) => {
                      if (event.key === "Enter") {
                        event.preventDefault();
                        submitMessage();
                      }
                    }}
                  />
                  <button type="button" className="gawago-chat-send-button" onClick={submitMessage} disabled={!draft.trim()}>
                    Send
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}
      </section>
    </div>
  );
}
