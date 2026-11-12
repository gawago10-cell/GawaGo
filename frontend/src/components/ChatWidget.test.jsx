import { afterEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";

const today = new Date();
const at = (daysAgo, hour, minute) => {
  const date = new Date(today.getFullYear(), today.getMonth(), today.getDate() - daysAgo, hour, minute);
  return date.toISOString();
};

vi.mock("../services/backendDataService", () => ({
  getConversations: vi.fn(async () => [
    {
      id: 5,
      jobTitle: "Taga ayos ng Aircon",
      statusLabel: "In progress",
      readOnly: false,
      otherPartyName: "Emman Aviles",
      otherPartyPhoto: "",
      lastMessage: { id: 3, content: "Bukas po ng 9 AM.", isMine: true },
      unreadCount: 0,
    },
    {
      id: 8,
      jobTitle: "Live-in helper",
      statusLabel: "In progress",
      readOnly: false,
      otherPartyName: "Emman Aviles",
      otherPartyPhoto: "",
      lastMessage: { id: 4, content: "Okay thank you po.", isMine: false },
      unreadCount: 2,
    },
  ]),
  getMessages: vi.fn(async (id) =>
    id === 5
      ? [
          {
            id: 1, content: "Kailan po kayo babalik?\nYung sa sala po.", isMine: false, isRead: true,
            senderName: "Emman Aviles", createdAt: at(1, 9, 5), status: "sent",
          },
          {
            id: 3, content: "Bukas po ng 9 AM.", isMine: true, isRead: true,
            senderName: "Reniel Bontoc", createdAt: at(0, 8, 0), status: "sent",
          },
        ]
      : [],
  ),
  markConversationRead: vi.fn(async () => ({})),
  sendMessage: vi.fn(async (id, content) => ({
    id: 99, content, isMine: true, isRead: false, senderName: "Reniel Bontoc", createdAt: new Date().toISOString(), status: "sent",
  })),
}));

import { getConversations, getMessages, sendMessage } from "../services/backendDataService";
import ChatWidget, { formatChatDay } from "./ChatWidget";

const worker = { role: "worker", username: "dashw" };

async function openChat() {
  render(<ChatWidget currentUser={worker} />);
  fireEvent.click(await screen.findByRole("button", { name: /Open chat/ }));
  return screen.findAllByText("Emman Aviles", { selector: ".gawago-chat-conversation-name strong" });
}

describe("ChatWidget", () => {
  afterEach(() => {
    vi.clearAllMocks();
    Object.defineProperty(document, "hidden", { configurable: true, value: false });
  });

  it("tells two chats with the same person apart by job, and says who wrote last", async () => {
    const names = await openChat();
    expect(names).toHaveLength(2);
    const [aircon, helper] = names.map((name) => name.closest("button"));
    expect(within(aircon).getByText("Taga ayos ng Aircon")).toBeTruthy();
    expect(aircon.textContent).toContain("You: Bukas po ng 9 AM.");
    expect(within(helper).getByText("Live-in helper")).toBeTruthy();
    expect(helper.textContent).not.toContain("You:");
    expect(within(helper).getByLabelText("2 unread").textContent).toBe("2");
  });

  it("keeps line breaks, shows day dividers, and drops the name from each bubble", async () => {
    await openChat();
    const incoming = await screen.findByText(/Kailan po kayo babalik/);
    expect(incoming.textContent).toBe("Kailan po kayo babalik?\nYung sa sala po.");
    const days = screen.getAllByRole("separator").map((element) => element.textContent);
    expect(days).toEqual(["Yesterday", "Today"]);
    const bubble = incoming.closest("article");
    expect(bubble.querySelector(".gawago-chat-bubble-meta").textContent).toBe("9:05 AM");
    // The name and job show once, in the header.
    expect(document.querySelector(".gawago-chat-thread-meta")).toBeNull();
  });

  it("sends on Enter, adds a line on Shift+Enter", async () => {
    await openChat();
    await screen.findByText(/Kailan po kayo babalik/);
    const box = screen.getByLabelText("Message Emman Aviles");
    expect(box.tagName).toBe("TEXTAREA");
    fireEvent.change(box, { target: { value: "Opo" } });
    fireEvent.keyDown(box, { key: "Enter", shiftKey: true });
    expect(sendMessage).not.toHaveBeenCalled();
    fireEvent.keyDown(box, { key: "Enter" });
    await waitFor(() => expect(sendMessage).toHaveBeenCalledWith(5, "Opo"));
  });

  it("has a labelled minimize button", async () => {
    await openChat();
    fireEvent.click(screen.getByRole("button", { name: "Minimize chat" }));
    expect(await screen.findByRole("button", { name: /Open chat/ })).toBeTruthy();
  });

  it("doesn't poll while the tab is hidden, and catches up when it's back", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    try {
      await openChat();
      await screen.findByText(/Kailan po kayo babalik/);
      Object.defineProperty(document, "hidden", { configurable: true, value: true });
      const messageCalls = getMessages.mock.calls.length;
      const listCalls = getConversations.mock.calls.length;
      await vi.advanceTimersByTimeAsync(61_000);
      expect(getMessages.mock.calls.length).toBe(messageCalls);
      expect(getConversations.mock.calls.length).toBe(listCalls);
      Object.defineProperty(document, "hidden", { configurable: true, value: false });
      document.dispatchEvent(new Event("visibilitychange"));
      await waitFor(() => expect(getMessages.mock.calls.length).toBeGreaterThan(messageCalls));
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("formatChatDay", () => {
  it("names the day", () => {
    const now = new Date(2026, 10, 12, 21, 0);
    expect(formatChatDay(new Date(2026, 10, 12, 0, 1).toISOString(), now)).toBe("Today");
    expect(formatChatDay(new Date(2026, 10, 11, 23, 0).toISOString(), now)).toBe("Yesterday");
    expect(formatChatDay(new Date(2026, 10, 1, 3, 0).toISOString(), now)).toBe("Nov 1, 2026");
    expect(formatChatDay("", now)).toBe("");
  });
});

describe("ChatWidget unread counts", () => {
  afterEach(() => vi.clearAllMocks());

  it("a list that answers late can't bring back a count just read", async () => {
    const { markConversationRead } = await import("../services/backendDataService");
    const list = (unread) => [
      {
        id: 8, jobTitle: "Live-in helper", statusLabel: "In progress", readOnly: false, otherPartyName: "Emman Aviles",
        otherPartyPhoto: "", lastMessage: { id: 4, content: "Okay thank you po.", isMine: false }, unreadCount: unread,
      },
      {
        id: 5, jobTitle: "Taga ayos ng Aircon", statusLabel: "In progress", readOnly: false, otherPartyName: "Emman Aviles",
        otherPartyPhoto: "", lastMessage: null, unreadCount: 0,
      },
    ];
    let releaseStale;
    getConversations
      .mockImplementationOnce(async () => list(1)) // first load
      .mockImplementationOnce(() => new Promise((resolve) => (releaseStale = () => resolve(list(1))))) // on open, slow
      .mockImplementation(async () => list(0)); // after "mark read"
    getMessages.mockImplementation(async (id) =>
      id === 8
        ? [{ id: 4, content: "Okay thank you po.", isMine: false, isRead: false, senderName: "Emman Aviles", createdAt: new Date().toISOString(), status: "sent" }]
        : [],
    );
    render(<ChatWidget currentUser={worker} />);
    fireEvent.click(await screen.findByRole("button", { name: /Open chat/ }));
    await waitFor(() => expect(markConversationRead).toHaveBeenCalledWith(8));
    await waitFor(() => expect(getConversations.mock.calls.length).toBeGreaterThanOrEqual(3));
    releaseStale();
    // Move to the other chat: the one just read shows no count.
    const [helper, aircon] = await screen.findAllByText("Emman Aviles", { selector: ".gawago-chat-conversation-name strong" });
    fireEvent.click(aircon.closest("button"));
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(within(helper.closest("button")).queryByLabelText("1 unread")).toBeNull();
  });
});
