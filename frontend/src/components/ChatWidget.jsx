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

function parseDate(value) {
  const date = value ? new Date(value) : null;
  return date && !Number.isNaN(date.getTime()) ? date : null;
}

function formatTime(value) {
  const date = parseDate(value);
  return date ? date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" }) : "";
}

// "Today", "Yesterday" or "Nov 1, 2026": the divider above a day's messages.
// Bubbles used to carry "Nov 12, 11:16 PM" with no year and no dividers.
export function formatChatDay(value, now = new Date()) {
  const date = parseDate(value);
  if (!date) return "";
  const startOfDay = (day) => new Date(day.getFullYear(), day.getMonth(), day.getDate()).getTime();
  const days = Math.round((startOfDay(now) - startOfDay(date)) / 86_400_000);
  if (days <= 0) return "Today";
  if (days === 1) return "Yesterday";
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

// Grows the message box with what's typed, up to the CSS max-height.
function fitDraftBox(element) {
  if (!element) return;
  element.style.height = "auto";
  element.style.height = `${element.scrollHeight}px`;
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
  const draftRef = useRef(null);
  messagesRef.current = messagesById;

  const activeConversation = conversations.find((conversation) => conversation.id === activeId) || null;
  const activeMessages = activeId ? messagesById[activeId] : undefined;
  const unreadTotal = useMemo(
    () => conversations.reduce((total, conversation) => total + (conversation.unreadCount || 0), 0),
    [conversations],
  );

  // Only the newest list request may write: an older one landing late put
  // back an unread count that had just been read.
  const refreshSeq = useRef(0);
  const refreshConversations = useCallback(async () => {
    const seq = ++refreshSeq.current;
    try {
      const next = await getConversations();
      if (seq !== refreshSeq.current) return;
      setConversations(next);
      setConversationsLoaded(true);
      setActiveId((current) => (next.some((conversation) => conversation.id === current) ? current : next[0]?.id ?? null));
    } catch {
      if (seq === refreshSeq.current) setConversationsLoaded(true);
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
    // Not while the tab is in the background: these polls kept going on
    // every hidden tab. Coming back catches up at once.
    const poll = () => {
      if (!document.hidden) refreshConversations();
    };
    const intervalId = window.setInterval(poll, CONVERSATION_POLL_MS);
    document.addEventListener("visibilitychange", poll);
    return () => {
      window.clearInterval(intervalId);
      document.removeEventListener("visibilitychange", poll);
    };
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
          // The list fetched while this was in flight still counts them unread.
          markConversationRead(conversationId)
            .then(() => refreshConversations())
            .catch(() => {});
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
    // Every 4 seconds while the thread is open, but not in a hidden tab.
    const poll = () => {
      if (!document.hidden) tick();
    };
    const intervalId = window.setInterval(poll, MESSAGE_POLL_MS);
    document.addEventListener("visibilitychange", poll);
    return () => {
      cancelled = true;
      window.clearInterval(intervalId);
      document.removeEventListener("visibilitychange", poll);
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
    window.requestAnimationFrame(() => fitDraftBox(draftRef.current));
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
          <button
            type="button"
            className="gawago-chat-toggle"
            aria-label="Minimize chat"
            title="Minimize chat"
            onClick={() => setCollapsed(true)}
          >
            <span className="material-symbols-outlined" aria-hidden="true">expand_more</span>
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
                    <div className="gawago-chat-conversation-name">
                      <strong title={conversation.otherPartyName}>{conversation.otherPartyName}</strong>
                      {conversation.unreadCount > 0 && conversation.id !== activeId ? (
                        <span
                          className="gawago-chat-unread-dot"
                          aria-label={`${conversation.unreadCount} unread`}
                        >
                          {conversation.unreadCount > 9 ? "9+" : conversation.unreadCount}
                        </span>
                      ) : null}
                    </div>
                    <span className="gawago-chat-conversation-job" title={conversation.jobTitle}>
                      {conversation.jobTitle}
                    </span>
                    {conversation.lastMessage ? (
                      <span className="gawago-chat-conversation-preview">
                        {conversation.lastMessage.isMine ? "You: " : ""}
                        {conversation.lastMessage.content}
                      </span>
                    ) : null}
                  </div>
                </button>
              ))}
            </aside>

            <div className="gawago-chat-thread">
              <div className="gawago-chat-messages" ref={messageBodyRef} aria-live="polite">
                {activeMessages === undefined ? (
                  <p className="gawago-chat-thread-note">Loading messages…</p>
                ) : activeMessages.length === 0 ? (
                  <p className="gawago-chat-thread-note">
                    {activeConversation?.readOnly
                      ? "No messages were sent for this job."
                      : `No messages yet. Send ${activeConversation?.otherPartyName || "them"} a message about ${activeConversation?.jobTitle || "the job"}.`}
                  </p>
                ) : (
                  activeMessages.map((message, index) => {
                    const day = formatChatDay(message.createdAt);
                    const showDay = day && day !== formatChatDay(activeMessages[index - 1]?.createdAt);
                    return (
                    <React.Fragment key={message.clientId || message.id}>
                    {showDay ? (
                      <p className="gawago-chat-day" role="separator">
                        <span>{day}</span>
                      </p>
                    ) : null}
                    <article
                      className={`gawago-chat-bubble ${message.isMine ? "outgoing" : "incoming"} ${message.status !== "sent" ? message.status : ""}`}
                      aria-label={message.isMine ? "You" : message.senderName}
                    >
                      <p>{message.content}</p>
                      <div className="gawago-chat-bubble-meta">
                        <span>
                          {message.status === "sending"
                            ? "Sending…"
                            : message.status === "failed"
                              ? "Not sent"
                              : formatTime(message.createdAt)}
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
                    </React.Fragment>
                    );
                  })
                )}
              </div>

              <div className="gawago-chat-composer">
                {loadError ? <p className="gawago-chat-load-error">{loadError}</p> : null}
                {activeConversation?.readOnly ? (
                  <p className="gawago-chat-read-only">This job is finished, so the chat is read only.</p>
                ) : (
                <div className="gawago-chat-composer-row gawago-chat-composer-row-text">
                  <textarea
                    id="gawago-chat-draft"
                    ref={draftRef}
                    rows={1}
                    value={draft}
                    maxLength={MAX_MESSAGE_LENGTH}
                    aria-label={activeConversation ? `Message ${activeConversation.otherPartyName}` : "Message"}
                    placeholder={activeConversation ? `Message ${activeConversation.otherPartyName}...` : "Type a message..."}
                    onChange={(event) => {
                      setDraft(event.target.value);
                      fitDraftBox(event.target);
                    }}
                    onKeyDown={(event) => {
                      // Enter sends; Shift+Enter is a new line (the phone app
                      // sends several lines, which the web joined into one).
                      if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
                        event.preventDefault();
                        submitMessage();
                      }
                    }}
                  />
                  <button type="button" className="gawago-chat-send-button" onClick={submitMessage} disabled={!draft.trim()}>
                    Send
                  </button>
                </div>
                )}
              </div>
            </div>
          </div>
        )}
      </section>
    </div>
  );
}
