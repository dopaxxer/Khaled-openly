/* eslint-disable @next/next/no-img-element -- Private media must retain session authorization and no-store access checks; uploaded images are resized before storage. */
/* eslint-disable react-hooks/set-state-in-effect -- Effects hydrate external session, network, and device draft state; updates are bounded by resource identity. */
"use client";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import type { Conversation, Cursor, Message } from "@/shared/types";
import {
  ArrowDown,
  ArrowLeft,
  BellOff,
  Flag,
  ImagePlus,
  Keyboard,
  MessageCircle,
  Mic,
  MoreHorizontal,
  Reply,
  Send,
  Square,
  X,
} from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import {
  api,
  errorText,
  imageUpload,
  upload,
  useAction,
  useApp,
  useResource,
} from "./context";
import { Report } from "./Posts";
import {
  Avatar,
  BusyButton,
  Button,
  Choice,
  EmptyState,
  ErrorState,
  IconButton,
  Loading,
} from "./primitives";
function Attachment({ id }: { id: string }) {
  const { t } = useApp();
  const [file, setFile] = useState<{ url: string; type: string } | null>(null),
    [failed, setFailed] = useState(false);
  useEffect(() => {
    let active = true;
    let object = "";
    fetch("/api/media/" + id)
      .then(async (r) => {
        if (!r.ok) throw new Error();
        const blob = await r.blob();
        object = URL.createObjectURL(blob);
        if (active) setFile({ url: object, type: blob.type });
        else URL.revokeObjectURL(object);
      })
      .catch(() => {
        if (active) setFailed(true);
      });
    return () => {
      active = false;
      if (object) URL.revokeObjectURL(object);
    };
  }, [id]);
  if (failed)
    return (
      <p className="small">{t("Attachment unavailable", "المرفق غير متاح")}</p>
    );
  if (!file)
    return (
      <span className="small">
        {t("Loading attachment…", "جارٍ تحميل المرفق…")}
      </span>
    );
  return file.type.startsWith("audio/") ? (
    <audio
      src={file.url}
      controls
      preload="none"
      aria-label={t("Voice message", "رسالة صوتية")}
    />
  ) : (
    <a href={file.url} target="_blank" rel="noreferrer">
      <img src={file.url} alt={t("Message image", "صورة الرسالة")} />
    </a>
  );
}
export function Messages({
  selected,
  setSelected,
  active,
}: {
  selected: string | null;
  setSelected: (id: string | null) => void;
  active: boolean;
}) {
  const { t } = useApp();
  const [filter, setFilter] = useState("all");
  const r = useResource<{ items: Conversation[] }>("conversations", {
    items: [],
  });
  useEffect(() => {
    if (!active) return;
    const timer = setInterval(r.reload, 10000);
    return () => clearInterval(timer);
  }, [active, r.reload]);
  if (selected)
    return (
      <Chat
        key={selected}
        cid={selected}
        active={active}
        onBack={() => {
          setSelected(null);
          r.reload();
        }}
        conversation={r.data.items.find((c) => c.id === selected)}
      />
    );
  return (
    <div className="page-content">
      <div className="row between">
        <h2>{t("Conversations", "المحادثات")}</h2>
        <Choice
          value={filter}
          onChange={setFilter}
          options={[
            ["all", t("All", "الكل")],
            ["pending", t("Requests", "الطلبات")],
          ]}
          label={t("Conversation filter", "تصفية المحادثات")}
        />
      </div>
      {r.loading ? (
        <Loading />
      ) : r.error ? (
        <ErrorState error={r.error} retry={r.reload} />
      ) : r.data.items.filter((c) => filter === "all" || c.status === "pending")
          .length ? (
        r.data.items
          .filter((c) => filter === "all" || c.status === "pending")
          .map((c) => (
            <button
              className="person-row w-full"
              style={{ textAlign: "start" }}
              key={c.id}
              onClick={() => setSelected(c.id)}
            >
              <Avatar name={c.name} src={c.avatar} />
              <div className="grow">
                <div className="row between">
                  <strong>{c.name}</strong>
                  {c.status === "pending" && (
                    <span className="badge">{t("Request", "طلب")}</span>
                  )}
                </div>
                <p className="meta" dir="auto">
                  {c.lastBody?.slice(0, 65) ||
                    t("Start a conversation", "ابدأ محادثة")}
                </p>
              </div>
              {!!c.muted && <BellOff />}
              {c.unread > 0 && <span className="badge">{c.unread}</span>}
            </button>
          ))
      ) : (
        <EmptyState
          icon={<MessageCircle />}
          title={t(
            "Good conversations start small.",
            "المحادثات الجميلة تبدأ ببساطة.",
          )}
          description={t(
            "Discover someone with a shared interest and say hello. New conversations appear here.",
            "اكتشف شخصًا يشاركك اهتمامًا وقل مرحبًا. ستظهر المحادثات الجديدة هنا.",
          )}
        />
      )}
    </div>
  );
}
function Chat({
  cid,
  active,
  onBack,
  conversation,
}: {
  cid: string;
  active: boolean;
  onBack: () => void;
  conversation?: Conversation;
}) {
  const { t, user, language, openProfile } = useApp();
  const [items, setItems] = useState<Message[]>([]),
    [pending, setPending] = useState<Message[]>([]),
    [loading, setLoading] = useState(true),
    [error, setError] = useState<unknown>(null),
    [draft, setDraft] = useState(""),
    [reply, setReply] = useState<Message | null>(null),
    [media, setMedia] = useState<string | null>(null),
    [uploading, setUploading] = useState(false),
    [status, setStatus] = useState(conversation?.status || "accepted"),
    [typing, setTyping] = useState(false),
    [cursor, setCursor] = useState<Cursor>(null),
    [newCount, setNewCount] = useState(0),
    [recording, setRecording] = useState(false),
    [muted, setMuted] = useState(!!conversation?.muted),
    [report, setReport] = useState<string | null>(null);
  const log = useRef<HTMLDivElement>(null),
    file = useRef<HTMLInputElement>(null),
    text = useRef<HTMLTextAreaElement>(null),
    recorder = useRef<MediaRecorder | null>(null),
    stream = useRef<MediaStream | null>(null),
    mounted = useRef(true),
    bottom = useRef(true),
    first = useRef(true),
    busyLoad = useRef(false),
    sendId = useRef(crypto.randomUUID()),
    sending = useRef(false),
    draftLoaded = useRef(false),
    recordTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const { busy, run } = useAction();
  const storageKey = "openly:" + user!.id + ":chat:" + cid;
  const load = useCallback(async () => {
    if (busyLoad.current) return;
    busyLoad.current = true;
    try {
      const data = await api<{
        items: Message[];
        typing: boolean;
        status: string;
        next: Cursor;
      }>("conversations/" + cid + "/messages");
      if (!mounted.current) return;
      setItems((prev) => {
        const known = new Set(prev.map((m) => m.id));
        const additions = data.items.filter(
          (m) => !known.has(m.id) && m.sender !== user!.id,
        ).length;
        if (!bottom.current && !first.current && additions)
          setNewCount((n) => n + additions);
        const all = new Map(prev.map((m) => [m.id, m]));
        for (const item of data.items) all.set(item.id, item);
        return Array.from(all.values()).sort(
          (a, b) => a.created - b.created || a.id.localeCompare(b.id),
        );
      });
      setPending((p) =>
        p.filter((m) => !data.items.some((x) => x.id === m.id)),
      );
      if (first.current) {
        setCursor(data.next);
        first.current = false;
      }
      setTyping(data.typing);
      setStatus(data.status);
      setError(null);
      setLoading(false);
      if (bottom.current)
        requestAnimationFrame(() => {
          if (log.current) log.current.scrollTop = log.current.scrollHeight;
        });
      const ids = data.items
        .filter(
          (m) =>
            m.sender !== user!.id &&
            (!m.delivered || (!m.read && bottom.current && active)),
        )
        .map((m) => m.id);
      if (ids.length)
        await api("conversations/" + cid + "/ack", "POST", {
          ids,
          read:
            bottom.current && active && document.visibilityState === "visible",
        });
    } catch (e) {
      if (mounted.current) {
        setError(e);
        setLoading(false);
      }
    } finally {
      busyLoad.current = false;
    }
  }, [cid, user, active]);
  useEffect(() => {
    mounted.current = true;
    void load();
    let events: EventSource | null = null;
    if (active) {
      events = new EventSource("/api/conversations/" + cid + "/events");
      events.addEventListener("update", load);
      events.onerror = () => {
        if (!navigator.onLine) setError(new Error("offline"));
      };
    }
    const onOnline = () => {
      void load();
    };
    window.addEventListener("online", onOnline);
    const interval = setInterval(() => {
      if (active) void load();
    }, 15000);
    return () => {
      mounted.current = false;
      events?.close();
      clearInterval(interval);
      window.removeEventListener("online", onOnline);
    };
  }, [cid, active, load]);
  useEffect(() => {
    const local = localStorage.getItem(storageKey);
    if (local !== null) {
      setDraft(local);
      draftLoaded.current = true;
    } else
      api<{ state: { draft: string; muted: number } | null }>(
        "conversations/" + cid + "/state",
      )
        .then((d) => {
          setDraft(d.state?.draft || "");
          setMuted(!!d.state?.muted);
          draftLoaded.current = true;
        })
        .catch(() => {
          draftLoaded.current = true;
        });
    return () => {
      if (recorder.current?.state === "recording") recorder.current.stop();
      stream.current?.getTracks().forEach((track) => track.stop());
      if (recordTimer.current) clearTimeout(recordTimer.current);
    };
  }, [cid, storageKey]);
  useEffect(() => {
    if (!draftLoaded.current) return;
    localStorage.setItem(storageKey, draft);
    const timer = setTimeout(() => {
      void api("conversations/" + cid + "/state", "PATCH", {
        draft,
        typing: !!draft,
      }).catch(() => {});
    }, 650);
    return () => clearTimeout(timer);
  }, [draft, cid, storageKey]);
  async function send(retry?: Message) {
    if (sending.current || (!retry && !draft.trim() && !media)) return;
    sending.current = true;
    const m: Message = retry || {
      id: sendId.current,
      conversationId: cid,
      sender: user!.id,
      body: draft,
      media,
      replyTo: reply?.id || null,
      created: Date.now(),
      delivered: null,
      read: null,
      localState: "pending",
    };
    setPending((p) => [
      ...p.filter((x) => x.id !== m.id),
      { ...m, localState: "pending" },
    ]);
    try {
      await api("conversations/" + cid + "/messages", "POST", {
        id: m.id,
        body: m.body,
        media: m.media,
        replyTo: m.replyTo,
      });
      if (!retry) {
        setDraft("");
        setMedia(null);
        setReply(null);
        localStorage.removeItem(storageKey);
        void api("conversations/" + cid + "/state", "PATCH", {
          draft: "",
          typing: false,
        }).catch(() => {});
        sendId.current = crypto.randomUUID();
      }
      bottom.current = true;
      await load();
    } catch (e) {
      setPending((p) =>
        p.map((x) => (x.id === m.id ? { ...x, localState: "failed" } : x)),
      );
      toast.error(errorText(e, language));
    } finally {
      sending.current = false;
    }
  }
  async function choose(f: File) {
    setUploading(true);
    try {
      setMedia((await imageUpload(f)).id);
    } catch (e) {
      toast.error(errorText(e, language));
    } finally {
      setUploading(false);
    }
  }
  async function record() {
    if (recording) {
      recorder.current?.stop();
      return;
    }
    try {
      if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
        toast.error(
          t(
            "Voice recording is unavailable in this browser.",
            "تسجيل الصوت غير متاح في هذا المتصفح.",
          ),
        );
        return;
      }
      stream.current = await navigator.mediaDevices.getUserMedia({
        audio: true,
      });
      const mime = [
        "audio/mp4",
        "audio/webm;codecs=opus",
        "audio/ogg;codecs=opus",
      ].find((v) => MediaRecorder.isTypeSupported(v));
      recorder.current = new MediaRecorder(
        stream.current,
        mime ? { mimeType: mime } : undefined,
      );
      const chunks: Blob[] = [];
      recorder.current.ondataavailable = (e) => {
        if (e.data.size) chunks.push(e.data);
      };
      recorder.current.onstop = async () => {
        stream.current?.getTracks().forEach((track) => track.stop());
        setRecording(false);
        if (recordTimer.current) clearTimeout(recordTimer.current);
        if (!mounted.current) return;
        setUploading(true);
        try {
          const blob = new Blob(chunks, {
            type: recorder.current?.mimeType.split(";")[0] || "audio/webm",
          });
          setMedia((await upload(blob)).id);
        } catch (e) {
          toast.error(errorText(e, language));
        } finally {
          setUploading(false);
        }
      };
      recorder.current.start();
      setRecording(true);
      recordTimer.current = setTimeout(
        () =>
          recorder.current?.state === "recording" && recorder.current.stop(),
        120000,
      );
    } catch {
      toast.error(
        t(
          "Microphone access was denied. Allow it in your browser settings, or send text.",
          "لم يُسمح بالميكروفون. فعّله من إعدادات المتصفح أو أرسل نصًا.",
        ),
      );
    }
  }
  const other = conversation?.other;
  const all = [
    ...items,
    ...pending.filter((p) => !items.some((m) => m.id === p.id)),
  ];
  return (
    <div className="chat-layout">
      <div className="chat-head">
        <IconButton
          label={t("Back", "رجوع")}
          onClick={() => {
            text.current?.blur();
            onBack();
          }}
        >
          <ArrowLeft />
        </IconButton>
        <button
          className="row grow"
          onClick={() => other && openProfile(other)}
          disabled={!other}
        >
          <Avatar name={conversation?.name || "O"} src={conversation?.avatar} />
          <div style={{ textAlign: "start" }}>
            <strong>{conversation?.name || t("Conversation", "محادثة")}</strong>
            <p className="meta">
              {typing
                ? t("Typing…", "يكتب الآن…")
                : status === "pending"
                  ? t("Message request", "طلب محادثة")
                  : t("Private conversation", "محادثة خاصة")}
            </p>
          </div>
        </button>
        <IconButton
          label={t("Dismiss keyboard", "إخفاء لوحة المفاتيح")}
          onClick={() => text.current?.blur()}
        >
          <Keyboard />
        </IconButton>
        <IconButton
          label={muted ? t("Unmute", "إلغاء الكتم") : t("Mute", "كتم")}
          onClick={() =>
            run(async () => {
              await api("conversations/" + cid + "/state", "PATCH", {
                muted: muted ? 0 : 1,
              });
              setMuted(!muted);
            })
          }
        >
          <BellOff className={muted ? "ink" : ""} />
        </IconButton>
      </div>
      {status === "pending" && (
        <div className="alert">
          <p>
            {conversation?.initiator === user!.id
              ? t(
                  "Your request is waiting. You can send one text introduction.",
                  "طلبك بانتظار القبول. يمكنك إرسال رسالة تعريفية واحدة.",
                )
              : t(
                  "Accept this request to start a conversation.",
                  "اقبل الطلب لبدء المحادثة.",
                )}
          </p>
          {conversation && conversation.initiator !== user!.id && (
            <div className="row">
              <BusyButton
                busy={busy}
                onClick={() =>
                  run(async () => {
                    await api("conversations/" + cid + "/accept", "POST");
                    setStatus("accepted");
                    await load();
                  })
                }
              >
                {t("Accept", "قبول")}
              </BusyButton>
              <Button
                variant="ghost"
                onClick={() =>
                  run(async () => {
                    await api("conversations/" + cid + "/decline", "POST");
                    setStatus("declined");
                  })
                }
              >
                {t("Decline", "رفض")}
              </Button>
            </div>
          )}
        </div>
      )}
      {status === "declined" && (
        <div className="alert">
          {t("This request was declined.", "تم رفض هذا الطلب.")}
        </div>
      )}
      <div
        className="chat-log"
        ref={log}
        onScroll={() => {
          if (!log.current) return;
          const el = log.current;
          bottom.current =
            el.scrollHeight - el.scrollTop - el.clientHeight < 100;
          if (bottom.current && newCount) {
            setNewCount(0);
            void load();
          }
        }}
      >
        {cursor && (
          <Button
            variant="ghost"
            disabled={busy}
            onClick={() =>
              run(async () => {
                const el = log.current!;
                const height = el.scrollHeight;
                const top = el.scrollTop;
                const data = await api<{ items: Message[]; next: Cursor }>(
                  "conversations/" +
                    cid +
                    "/messages?" +
                    new URLSearchParams({
                      before: String(cursor.before),
                      cursor: cursor.cursor,
                    }),
                );
                setItems((current) => [
                  ...data.items.filter(
                    (m) => !current.some((x) => x.id === m.id),
                  ),
                  ...current,
                ]);
                setCursor(data.next);
                requestAnimationFrame(() => {
                  el.scrollTop = top + el.scrollHeight - height;
                });
              })
            }
          >
            {t("Earlier messages", "رسائل أقدم")}
          </Button>
        )}
        {loading ? (
          <Loading />
        ) : error ? (
          <ErrorState error={error} retry={load} />
        ) : !all.length ? (
          <EmptyState
            icon={<MessageCircle />}
            title={t("Say something simple.", "ابدأ بكلمة بسيطة.")}
            description={t(
              "A shared interest is a good place to start.",
              "اهتمام مشترك قد يكون بداية جميلة.",
            )}
          />
        ) : null}
        {all.map((m) => (
          <div
            className={"bubble " + (m.sender === user!.id ? "mine" : "")}
            key={m.id}
          >
            {m.replyTo && (
              <div
                className="meta"
                style={{
                  borderInlineStart: "2px solid var(--primary)",
                  paddingInlineStart: 8,
                  marginBottom: 7,
                }}
              >
                {t("Reply to", "رد على")}:{" "}
                {items.find((x) => x.id === m.replyTo)?.body.slice(0, 80) ||
                  t("Earlier message", "رسالة سابقة")}
              </div>
            )}
            {m.media && <Attachment id={m.media} />}
            <p dir="auto">{m.body}</p>
            <div className="row between">
              <span className="message-state">
                {new Intl.DateTimeFormat(language, {
                  hour: "numeric",
                  minute: "2-digit",
                }).format(m.created)}
                {m.sender === user!.id &&
                  " · " +
                    (m.localState === "pending"
                      ? t("Pending", "قيد الإرسال")
                      : m.localState === "failed"
                        ? t("Failed", "تعذّر الإرسال")
                        : m.read
                          ? t("Read", "مقروءة")
                          : m.delivered
                            ? t("Delivered", "تم التسليم")
                            : t("Sent", "تم الإرسال"))}
              </span>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <button
                    style={{ minHeight: 32, minWidth: 32 }}
                    aria-label={t("Message actions", "خيارات الرسالة")}
                  >
                    <MoreHorizontal width={17} />
                  </button>
                </DropdownMenuTrigger>
                <DropdownMenuContent>
                  <DropdownMenuItem
                    onSelect={() => {
                      setReply(m);
                      text.current?.focus();
                    }}
                  >
                    <Reply />
                    {t("Reply", "رد")}
                  </DropdownMenuItem>
                  {["♥", "👍", "✨", "😂"].map((emoji) => (
                    <DropdownMenuItem
                      key={emoji}
                      onSelect={() =>
                        run(async () => {
                          await api("messages/" + m.id + "/reaction", "POST", {
                            emoji,
                          });
                          await load();
                        })
                      }
                    >
                      {emoji}
                    </DropdownMenuItem>
                  ))}
                  {m.sender !== user!.id && (
                    <DropdownMenuItem onSelect={() => setReport(m.id)}>
                      <Flag />
                      {t("Report", "إبلاغ")}
                    </DropdownMenuItem>
                  )}
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
            {m.reactions?.map((r) => (
              <button
                key={r.userId}
                className="reaction"
                onClick={() => {
                  if (r.userId === user!.id)
                    void run(async () => {
                      await api("messages/" + m.id + "/reaction", "POST", {
                        emoji: "",
                      });
                      await load();
                    });
                }}
                aria-label={t("Reaction", "تفاعل")}
              >
                {r.emoji}
              </button>
            ))}
            {m.localState === "failed" && (
              <button className="small ink" onClick={() => send(m)}>
                {t("Retry", "إعادة المحاولة")}
              </button>
            )}
          </div>
        ))}
        {newCount > 0 && (
          <Button
            className="floating-message"
            onClick={() => {
              bottom.current = true;
              setNewCount(0);
              if (log.current) log.current.scrollTop = log.current.scrollHeight;
              void load();
            }}
          >
            <ArrowDown />
            {t("New messages", "رسائل جديدة")} ({newCount})
          </Button>
        )}
      </div>
      <form
        className="chat-compose"
        onSubmit={(e) => {
          e.preventDefault();
          void send();
        }}
      >
        {reply && (
          <div className="row between alert">
            <span className="small">
              {t("Replying to", "رد على")}: {reply.body.slice(0, 60)}
            </span>
            <IconButton
              label={t("Cancel reply", "إلغاء الرد")}
              onClick={() => setReply(null)}
            >
              <X />
            </IconButton>
          </div>
        )}
        {media && (
          <div className="row">
            <span className="badge">
              {t("Attachment ready", "المرفق جاهز")}
            </span>
            <IconButton
              label={t("Remove attachment", "إزالة المرفق")}
              onClick={() => setMedia(null)}
            >
              <X />
            </IconButton>
          </div>
        )}
        <div className="row" style={{ gap: 5 }}>
          <IconButton
            label={t("Add image", "إضافة صورة")}
            disabled={uploading || status !== "accepted"}
            onClick={() => file.current?.click()}
          >
            <ImagePlus />
          </IconButton>
          <textarea
            ref={text}
            rows={1}
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            maxLength={5000}
            placeholder={t("Write a message…", "اكتب رسالة…")}
            aria-label={t("Message", "الرسالة")}
            dir="auto"
            disabled={status === "declined"}
          />
          <IconButton
            label={
              recording
                ? t("Stop recording", "إيقاف التسجيل")
                : t("Record voice message", "تسجيل رسالة صوتية")
            }
            disabled={uploading || status !== "accepted"}
            onClick={record}
          >
            {recording ? <Square className="error" /> : <Mic />}
          </IconButton>
          <Button
            type="submit"
            size="icon"
            aria-label={t("Send message", "إرسال الرسالة")}
            disabled={
              uploading ||
              recording ||
              status === "declined" ||
              (!draft.trim() && !media)
            }
          >
            <Send />
          </Button>
        </div>
        {recording && (
          <p className="small error" role="status">
            {t(
              "Recording… tap stop when you’re done. Maximum 2 minutes.",
              "جارٍ التسجيل… اضغط إيقاف عند الانتهاء. الحد الأقصى دقيقتان.",
            )}
          </p>
        )}
        {uploading && (
          <p className="meta" role="status">
            {t("Uploading attachment…", "جارٍ رفع المرفق…")}
          </p>
        )}
        <input
          ref={file}
          type="file"
          accept="image/*"
          hidden
          onChange={(e) => {
            if (e.target.files?.[0]) void choose(e.target.files[0]);
            e.target.value = "";
          }}
        />
      </form>
      {report && (
        <Report
          kind="message"
          target={report}
          onClose={() => setReport(null)}
        />
      )}
    </div>
  );
}
