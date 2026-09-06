import React, { useEffect, useMemo, useRef, useState } from "react";

function getInitials(name) {
  return String(name || "U")
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() || "")
    .join("");
}

export default function FloatingChatWidget({
  conversations,
  currentConversationId,
  messagesByConversation,
  onSelectConversation,
  onSendMessage,
}) {
  const [collapsed, setCollapsed] = useState(true);
  const [draft, setDraft] = useState("");
  const [pendingImage, setPendingImage] = useState(null);
  const [profileOpen, setProfileOpen] = useState(false);
  const [lastSeenAt, setLastSeenAt] = useState(() => Date.now());
  const fileInputRef = useRef(null);
  const messageBodyRef = useRef(null);

  const activeConversation =
    conversations.find((conversation) => String(conversation.id) === String(currentConversationId)) || conversations[0] || null;
  const activeMessages = activeConversation ? messagesByConversation[activeConversation.id] || [] : [];
  const lastMessage = activeMessages[activeMessages.length - 1] || null;
  const allMessages = useMemo(
    () => Object.values(messagesByConversation).flat(),
    [messagesByConversation],
  );
  const unreadCount = useMemo(() => {
    if (!collapsed) {
      return 0;
    }
    return allMessages.filter(
      (message) =>
        !message.isCurrentUser &&
        message.senderRole !== "system" &&
        message.createdAt &&
        new Date(message.createdAt).getTime() > lastSeenAt,
    ).length;
  }, [allMessages, collapsed, lastSeenAt]);
  useEffect(() => {
    if (!messageBodyRef.current || collapsed) {
      return;
    }
    messageBodyRef.current.scrollTop = messageBodyRef.current.scrollHeight;
  }, [activeConversation?.id, activeMessages, collapsed]);
  useEffect(() => {
    setProfileOpen(false);
  }, [activeConversation?.id]);
  useEffect(() => {
    if (!collapsed) {
      setLastSeenAt(Date.now());
    }
  }, [collapsed, allMessages]);

  if (!conversations.length) {
    return null;
  }

  const submitMessage = () => {
    if (!activeConversation) {
      return;
    }
    const trimmedDraft = draft.trim();
    if (!trimmedDraft && !pendingImage) {
      return;
    }
    onSendMessage(activeConversation.id, {
      text: trimmedDraft,
      imageUrl: pendingImage?.dataUrl || "",
      imageName: pendingImage?.name || "",
    });
    setDraft("");
    setPendingImage(null);
    if (fileInputRef.current) {
      fileInputRef.current.value = "";
    }
  };

  const handleImageChange = (event) => {
    const [file] = event.target.files || [];
    if (!file) {
      setPendingImage(null);
      return;
    }
    const reader = new FileReader();
    reader.onload = (loadEvent) => {
      setPendingImage({
        name: file.name,
        dataUrl: String(loadEvent.target?.result || ""),
      });
    };
    reader.readAsDataURL(file);
  };

  if (collapsed) {
    return (
      <div className="gawago-chat-dock gawago-chat-dock-collapsed" aria-label="Household and worker chat">
        <button
          type="button"
          className="gawago-chat-fab"
          aria-label={unreadCount > 0 ? `Open chat, ${unreadCount} new message${unreadCount > 1 ? "s" : ""}` : "Open chat"}
          onClick={() => setCollapsed(false)}
        >
          <span className="material-symbols-outlined" aria-hidden="true">
            chat
          </span>
          {unreadCount > 0 ? (
            <span className="gawago-chat-fab-badge">{unreadCount > 9 ? "9+" : unreadCount}</span>
          ) : null}
        </button>
      </div>
    );
  }

  return (
    <div className="gawago-chat-dock" aria-label="Household and worker chat">
      <section className="gawago-chat-panel">
        <header className="gawago-chat-panel-head">
          <div className="gawago-chat-panel-identity">
            <button
              type="button"
              className="gawago-chat-profile-trigger"
              aria-label={`View ${activeConversation?.otherPartyName || "profile"} profile`}
              onClick={() => setProfileOpen((value) => !value)}
            >
              {activeConversation?.otherPartyPhoto ? (
                <img src={activeConversation.otherPartyPhoto} alt={activeConversation.otherPartyName} />
              ) : (
                <span>{getInitials(activeConversation?.otherPartyName)}</span>
              )}
            </button>
            <div className="gawago-chat-panel-title">
              <strong>{activeConversation?.otherPartyName || "Messages"}</strong>
              <span>
                {activeConversation?.statusLabel || "Chat open"} • {activeConversation?.rateLabel || "Rate pending"}
              </span>
            </div>
          </div>
          <button
            type="button"
            className="gawago-chat-toggle"
            aria-label="Collapse chat"
            onClick={() => setCollapsed(true)}
          >
            -
          </button>
        </header>

        <div className="gawago-chat-panel-body">
          <aside className="gawago-chat-conversation-list">
            {conversations.map((conversation) => {
              const conversationMessages = messagesByConversation[conversation.id] || [];
              const previewMessage = conversationMessages[conversationMessages.length - 1];
              const isActive = activeConversation && String(activeConversation.id) === String(conversation.id);
              return (
                <button
                  key={conversation.id}
                  type="button"
                  className={`gawago-chat-conversation-item ${isActive ? "active" : ""}`}
                  onClick={() => onSelectConversation(conversation.id)}
                >
                  <div className="gawago-chat-conversation-avatar">
                    {conversation.otherPartyPhoto ? (
                      <img src={conversation.otherPartyPhoto} alt={conversation.otherPartyName} />
                    ) : (
                      <span>{getInitials(conversation.otherPartyName)}</span>
                    )}
                  </div>
                  <div className="gawago-chat-conversation-copy">
                    <strong>{conversation.otherPartyName}</strong>
                    <span>{previewMessage?.text || (previewMessage?.imageUrl ? "Shared a photo" : conversation.jobTitle)}</span>
                  </div>
                </button>
              );
            })}
          </aside>

          <div className="gawago-chat-thread">
            <div className="gawago-chat-thread-meta">
              <strong>{activeConversation?.otherPartyName}</strong>
              <span>
                {activeConversation?.jobTitle || "Chat"} • {activeConversation?.statusLabel || "Chat open"}
              </span>
            </div>

            <div className="gawago-chat-messages" ref={messageBodyRef}>
              {activeMessages.map((message) => (
                <article
                  key={message.id}
                  className={`gawago-chat-bubble ${
                    message.senderRole === "system"
                      ? "system"
                      : message.isCurrentUser
                        ? "outgoing"
                        : "incoming"
                  }`}
                >
                  {message.text ? <p>{message.text}</p> : null}
                  {message.imageUrl ? (
                    <figure className="gawago-chat-image">
                      <img src={message.imageUrl} alt={message.imageName || "Shared chat attachment"} />
                      <figcaption>{message.imageName || "Picture attachment"}</figcaption>
                    </figure>
                  ) : null}
                  <div className="gawago-chat-bubble-meta">
                    <span>{message.senderLabel}</span>
                    <span>{message.createdAtLabel}</span>
                  </div>
                </article>
              ))}
            </div>

            <div className="gawago-chat-composer">
              {pendingImage ? (
                <div className="gawago-chat-attachment-preview">
                  <img src={pendingImage.dataUrl} alt={pendingImage.name} />
                  <div>
                    <strong>Picture ready</strong>
                    <span>{pendingImage.name}</span>
                  </div>
                  <button
                    type="button"
                    className="gawago-chat-attachment-remove"
                    onClick={() => {
                      setPendingImage(null);
                      if (fileInputRef.current) {
                        fileInputRef.current.value = "";
                      }
                    }}
                  >
                    x
                  </button>
                </div>
              ) : null}

              <div className="gawago-chat-composer-row">
                <input
                  type="text"
                  value={draft}
                  placeholder={activeConversation ? `Message ${activeConversation.otherPartyName}...` : "Type a message..."}
                  onChange={(event) => setDraft(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") {
                      event.preventDefault();
                      submitMessage();
                    }
                  }}
                />
                <label className="gawago-chat-attach-button">
                  <input ref={fileInputRef} type="file" accept="image/*" onChange={handleImageChange} />
                  <span className="material-symbols-outlined" aria-hidden="true">photo_library</span>
                  <span className="visually-hidden">Attach picture</span>
                </label>
                <button type="button" className="gawago-chat-send-button" onClick={submitMessage}>
                  Send
                </button>
              </div>
            </div>
          </div>
        </div>

        {lastMessage ? <div className="gawago-chat-footer-note">Latest update: {lastMessage.createdAtLabel}</div> : null}
      </section>

      {profileOpen && activeConversation ? (
        <div className="gawago-chat-profile-modal-backdrop" onClick={() => setProfileOpen(false)}>
          <div className="gawago-chat-profile-modal" onClick={(event) => event.stopPropagation()}>
            <div className="gawago-chat-profile-modal-head">
              <div className="gawago-chat-profile-card-head">
                <div className="gawago-chat-profile-avatar">
                  {activeConversation.otherPartyPhoto ? (
                    <img src={activeConversation.otherPartyPhoto} alt={activeConversation.otherPartyName} />
                  ) : (
                    <span>{getInitials(activeConversation.otherPartyName)}</span>
                  )}
                </div>
                <div className="gawago-chat-profile-copy">
                  <strong>{activeConversation.otherPartyName}</strong>
                  <span>{activeConversation.otherPartyRole === "worker" ? "Worker Profile" : "Household Profile"}</span>
                </div>
              </div>
              <button
                type="button"
                className="gawago-chat-profile-close"
                aria-label="Close profile"
                onClick={() => setProfileOpen(false)}
              >
                x
              </button>
            </div>
            <div className="gawago-chat-profile-grid">
              <div>
                <strong>Location</strong>
                <span>{activeConversation.otherPartyProfile?.location || "Location not available"}</span>
              </div>
              <div>
                <strong>Verification</strong>
                <span>{activeConversation.otherPartyProfile?.verification || "Not available"}</span>
              </div>
              <div>
                <strong>Rate</strong>
                <span>{activeConversation.otherPartyProfile?.rate || "Rate not available"}</span>
              </div>
              <div>
                <strong>Contact</strong>
                <span>
                  {activeConversation.otherPartyProfile?.phone || activeConversation.otherPartyProfile?.email || "No contact details"}
                </span>
              </div>
            </div>
            {activeConversation.otherPartyProfile?.skills?.length ? (
              <div className="gawago-chat-profile-skills">
                {activeConversation.otherPartyProfile.skills.map((skill) => (
                  <span key={skill}>{skill}</span>
                ))}
              </div>
            ) : null}
            <p className="gawago-chat-profile-bio">{activeConversation.otherPartyProfile?.bio || "No background provided yet."}</p>
          </div>
        </div>
      ) : null}
    </div>
  );
}
