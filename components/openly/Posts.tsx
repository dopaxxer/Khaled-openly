/* eslint-disable @next/next/no-img-element -- Private media must retain session authorization and no-store access checks; uploaded images are resized before storage. */
/* eslint-disable react-hooks/set-state-in-effect -- Effects hydrate external session, network, and device draft state; updates are bounded by resource identity. */
"use client";
import {
  Command,
  CommandEmpty,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import type { Cursor, Post, Song } from "@/shared/types";
import {
  Bookmark,
  Camera,
  EyeOff,
  Feather,
  Flag,
  Heart,
  ImagePlus,
  Lock,
  MessageCircle,
  MoreHorizontal,
  Music2,
  Pin,
  Plus,
  Send,
  Trash2,
  Upload,
  X,
} from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import {
  api,
  RequestError,
  dateLabel,
  errorText,
  imageUpload,
  useAction,
  useApp,
  useResource,
} from "./context";
import {
  Avatar,
  BusyButton,
  Button,
  Choice,
  Confirm,
  EmptyState,
  ErrorState,
  IconButton,
  Loading,
  Modal,
  SongCard,
} from "./primitives";
export function SongPicker({
  open,
  onClose,
  onPick,
}: {
  open: boolean;
  onClose: () => void;
  onPick: (s: Song) => void;
}) {
  const { t } = useApp();
  const [query, setQuery] = useState(""),
    [term, setTerm] = useState("");
  useEffect(() => {
    const timer = setTimeout(() => setTerm(query), 350);
    return () => clearTimeout(timer);
  }, [query]);
  const r = useResource<{ items: Song[] }>(
    open && term.length >= 2 ? "music?q=" + encodeURIComponent(term) : null,
    { items: [] },
  );
  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t("Find a song", "ابحث عن أغنية")}
      description={t(
        "Apple Music metadata and available previews. No automatic playback.",
        "بيانات Apple Music والمقتطفات المتاحة، دون تشغيل تلقائي.",
      )}
    >
      <Command shouldFilter={false}>
        <CommandInput
          placeholder={t("Song or artist", "أغنية أو فنان")}
          value={query}
          onValueChange={setQuery}
        />
        <CommandList>
          {r.loading ? (
            <Loading />
          ) : r.error ? (
            <ErrorState error={r.error} retry={r.reload} />
          ) : (
            <>
              <CommandEmpty>
                {term.length < 2
                  ? t("Type at least two characters.", "اكتب حرفين على الأقل.")
                  : t("No songs found.", "لم نجد أغاني.")}
              </CommandEmpty>
              {r.data.items.map((s) => (
                <CommandItem
                  key={s.id}
                  value={String(s.id)}
                  onSelect={() => {
                    onPick(s);
                    onClose();
                  }}
                >
                  <img src={s.artwork} width={40} height={40} alt="" />
                  <span>
                    <strong dir="auto">{s.title}</strong>
                    <p className="meta" dir="auto">
                      {s.artist}
                    </p>
                  </span>
                </CommandItem>
              ))}
            </>
          )}
        </CommandList>
      </Command>
    </Modal>
  );
}
export function Composer({
  open,
  onClose,
  kind = "post",
  circleId,
  edit,
}: {
  open: boolean;
  onClose: () => void;
  kind?: string;
  circleId?: string;
  edit?: Post | null;
}) {
  const { t, user, bump, language } = useApp();
  const [body, setBody] = useState(""),
    [song, setSong] = useState<Song | null>(null),
    [image, setImage] = useState<string | null>(null),
    [audience, setAudience] = useState("public"),
    [mood, setMood] = useState(""),
    [music, setMusic] = useState(false),
    [uploading, setUploading] = useState(false);
  const { busy, run } = useAction();
  const ready = useRef(false),
    key = useRef(crypto.randomUUID());
  const input = useRef<HTMLInputElement>(null),
    camera = useRef<HTMLInputElement>(null);
  const draftKey = kind + "_" + (circleId || "general");
  const localKey = "openly:" + user!.id + ":" + draftKey;
  useEffect(() => {
    if (!open) return;
    ready.current = false;
    key.current = crypto.randomUUID();
    if (edit) {
      setBody(edit.body);
      setAudience(edit.audience);
      setSong(edit.song);
      setImage(edit.image);
      ready.current = true;
      return;
    }
    const local = localStorage.getItem(localKey);
    const apply = (
      d: Partial<{
        body: string;
        song: Song | null;
        image: string | null;
        audience: string;
        mood: string;
        id: string;
      }>,
    ) => {
      setBody(d.body || "");
      setSong(d.song || null);
      setImage(d.image || null);
      setAudience(d.audience || "public");
      setMood(d.mood || "");
      if (d.id) key.current = d.id;
      ready.current = true;
    };
    if (local) {
      try {
        apply(JSON.parse(local));
      } catch {
        apply({});
      }
    } else
      api<{
        value: Partial<{
          body: string;
          song: Song | null;
          image: string | null;
          audience: string;
          mood: string;
          id: string;
        }>;
      }>("drafts/" + draftKey)
        .then((d) => apply(d.value))
        .catch(() => apply({}));
  }, [open, edit, localKey, draftKey]);
  useEffect(() => {
    if (!open || !ready.current || edit) return;
    const value = { body, song, image, audience, mood, id: key.current };
    localStorage.setItem(localKey, JSON.stringify(value));
    const timer = setTimeout(() => {
      void api("drafts/" + draftKey, "PUT", value).catch(() => {});
    }, 700);
    return () => clearTimeout(timer);
  }, [body, song, image, audience, mood, open, edit, localKey, draftKey]);
  async function choose(file: File) {
    setUploading(true);
    try {
      setImage((await imageUpload(file)).id);
    } catch (e) {
      toast.error(errorText(e, language));
    } finally {
      setUploading(false);
    }
  }
  async function submit() {
    await run(async () => {
      if (edit) await api("posts/" + edit.id, "PATCH", { body, audience });
      else
        await api("posts", "POST", {
          id: key.current,
          body,
          image,
          song,
          audience,
          circleId: circleId || null,
          kind,
          mood: mood || null,
        });
      localStorage.removeItem(localKey);
      if (!edit) await api("drafts/" + draftKey, "DELETE").catch(() => {});
      ready.current = false;
      setBody("");
      setImage(null);
      setSong(null);
      bump();
      toast.success(t("Shared with your people.", "تمت المشاركة."));
      onClose();
    });
  }
  return (
    <>
      <Modal
        open={open}
        onClose={onClose}
        title={
          edit
            ? t("Edit post", "تعديل المنشور")
            : kind === "moment"
              ? t("A little moment", "لحظة من يومك")
              : kind === "question"
                ? t("Ask your Circle", "اسأل دائرتك")
                : t("A thought to share", "فكرة تستحق المشاركة")
        }
      >
        <div className="stack">
          <div className="row">
            <Avatar name={user!.name} src={user!.avatar} />
            <div>
              <strong>{user!.name}</strong>
              <p className="meta">
                {kind === "moment" ? (
                  t("Visible for 24 hours", "متاحة لمدة 24 ساعة")
                ) : (
                  <bdi>@{user!.username}</bdi>
                )}
              </p>
            </div>
          </div>
          <Textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            maxLength={1500}
            placeholder={t("What’s on your mind?", "بماذا تفكر؟")}
            aria-label={t("Post text", "نص المنشور")}
            dir="auto"
          />
          {image && (
            <div className="relative">
              <img
                className="post-image"
                src={"/api/media/" + image}
                alt={t("Selected image", "الصورة المختارة")}
              />
              {!edit && (
                <IconButton
                  label={t("Remove image", "إزالة الصورة")}
                  onClick={() => setImage(null)}
                >
                  <X />
                </IconButton>
              )}
            </div>
          )}
          {song && (
            <div>
              <SongCard song={song} />
              {!edit && (
                <Button variant="ghost" onClick={() => setSong(null)}>
                  {t("Remove song", "إزالة الأغنية")}
                </Button>
              )}
            </div>
          )}
          {kind === "moment" && (
            <label className="small">
              {t("Mood (optional)", "المزاج (اختياري)")}
              <Input
                value={mood}
                maxLength={40}
                onChange={(e) => setMood(e.target.value)}
                placeholder={t("Feeling…", "أشعر بـ…")}
              />
            </label>
          )}
          <div className="row between wrap">
            <div className="row">
              {!edit && (
                <>
                  <IconButton
                    label={t("Add image", "إضافة صورة")}
                    disabled={uploading}
                    onClick={() => input.current?.click()}
                  >
                    <ImagePlus />
                  </IconButton>
                  <IconButton
                    label={t("Take photo", "التقاط صورة")}
                    disabled={uploading}
                    onClick={() => camera.current?.click()}
                  >
                    <Camera />
                  </IconButton>
                  <IconButton
                    label={t("Add song", "إضافة أغنية")}
                    onClick={() => setMusic(true)}
                  >
                    <Music2 />
                  </IconButton>
                </>
              )}
              <span className="meta">{body.length}/1500</span>
            </div>
            <Choice
              value={audience}
              onChange={setAudience}
              label={t("Audience", "الجمهور")}
              options={[
                ["public", t("Everyone", "الجميع")],
                ["followers", t("Followers", "المتابعون")],
                ["only_me", t("Only me", "أنا فقط")],
              ]}
            />
          </div>
          {user!.private === 1 && (
            <p className="meta">
              {t(
                "Your private account limits posts to approved followers.",
                "حسابك الخاص يقيّد الوصول إلى منشوراتك بالمتابعين المقبولين.",
              )}
            </p>
          )}
          <BusyButton
            busy={busy || uploading}
            disabled={!body.trim() && !image && !song}
            onClick={submit}
          >
            {uploading
              ? t("Uploading…", "جارٍ الرفع…")
              : edit
                ? t("Save changes", "حفظ التغييرات")
                : kind === "moment"
                  ? t("Share for 24 hours", "مشاركة لمدة 24 ساعة")
                  : t("Share post", "مشاركة المنشور")}
          </BusyButton>
          <input
            ref={input}
            type="file"
            accept="image/*"
            hidden
            onChange={(e) => {
              if (e.target.files?.[0]) void choose(e.target.files[0]);
              e.target.value = "";
            }}
          />
          <input
            ref={camera}
            type="file"
            accept="image/*"
            capture="environment"
            hidden
            onChange={(e) => {
              if (e.target.files?.[0]) void choose(e.target.files[0]);
              e.target.value = "";
            }}
          />
        </div>
      </Modal>
      <SongPicker
        open={music}
        onClose={() => setMusic(false)}
        onPick={setSong}
      />
    </>
  );
}
export function Report({
  kind,
  target,
  onClose,
}: {
  kind: string;
  target: string;
  onClose: () => void;
}) {
  const { t } = useApp();
  const [reason, setReason] = useState("");
  const { busy, run } = useAction();
  return (
    <Modal
      open
      title={t("Report content", "الإبلاغ عن محتوى")}
      onClose={onClose}
    >
      <div className="stack">
        <Textarea
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          minLength={3}
          maxLength={1000}
          placeholder={t(
            "What should the moderation team know?",
            "ما الذي ينبغي أن يعرفه فريق الإشراف؟",
          )}
          aria-label={t("Reason for report", "سبب الإبلاغ")}
        />
        <BusyButton
          busy={busy}
          disabled={reason.trim().length < 3}
          onClick={() =>
            run(async () => {
              await api("reports", "POST", { kind, target, reason });
              toast.success(t("Report received.", "تم استلام البلاغ."));
              onClose();
            })
          }
        >
          {t("Send report", "إرسال البلاغ")}
        </BusyButton>
      </div>
    </Modal>
  );
}
export function SavePost({
  post,
  onClose,
}: {
  post: Post;
  onClose: () => void;
}) {
  const { t, bump } = useApp();
  const r = useResource<{
    items: { id: string; name: string; count: number }[];
  }>("collections", { items: [] });
  const [name, setName] = useState("");
  const { busy, run } = useAction();
  return (
    <Modal
      open
      onClose={onClose}
      title={t("Save to a collection", "حفظ في مجموعة")}
      description={t(
        "Your collections are visible only to you.",
        "مجموعاتك خاصة بك وحدك.",
      )}
    >
      <div className="stack">
        {r.loading ? (
          <Loading />
        ) : (
          r.data.items.map((c) => (
            <Button
              variant="outline"
              key={c.id}
              disabled={busy}
              onClick={() =>
                run(async () => {
                  await api("collections/" + c.id + "/" + post.id, "POST");
                  bump();
                  toast.success(t("Saved.", "تم الحفظ."));
                  onClose();
                })
              }
            >
              <Bookmark />
              {c.name}
            </Button>
          ))
        )}
        {!!r.error && <ErrorState error={r.error} retry={r.reload} />}
        <form
          className="row"
          onSubmit={(e) => {
            e.preventDefault();
            void run(async () => {
              const result = await api<{ id: string }>("collections", "POST", {
                name,
              });
              await api("collections/" + result.id + "/" + post.id, "POST");
              bump();
              onClose();
            });
          }}
        >
          <Input
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={60}
            required
            placeholder={t("New collection name", "اسم المجموعة الجديدة")}
            aria-label={t("Collection name", "اسم المجموعة")}
          />
          <BusyButton type="submit" busy={busy}>
            <Plus />
          </BusyButton>
        </form>
      </div>
    </Modal>
  );
}
export function PostCard({
  post,
  onRemoved,
}: {
  post: Post;
  detail?: boolean;
  onRemoved?: () => void;
}) {
  const { t, user, bump, language, openPost, openProfile } = useApp();
  const { busy, run } = useAction();
  const [liked, setLiked] = useState(!!post.liked),
    [count, setCount] = useState(post.likes || 0),
    [image, setImage] = useState(false),
    [saved, setSaved] = useState(false),
    [editing, setEditing] = useState(false),
    [deleting, setDeleting] = useState(false),
    [report, setReport] = useState(false);
  useEffect(() => {
    setLiked(!!post.liked);
    setCount(post.likes || 0);
  }, [post.liked, post.likes]);
  async function like() {
    if (busy) return;
    const prev = liked;
    setLiked(!prev);
    setCount((n) => n + (prev ? -1 : 1));
    const result = await run(async () => {
      await api("posts/" + post.id + "/like", prev ? "DELETE" : "POST");
      return true;
    });
    if (!result) {
      setLiked(prev);
      setCount((n) => n + (prev ? 1 : -1));
    }
  }
  async function share() {
    await run(async () => {
      const url = location.origin + "/?post=" + post.id;
      if (navigator.share) {
        try {
          await navigator.share({ title: "Openly", url });
        } catch (e) {
          if ((e as Error).name !== "AbortError") throw e;
        }
      } else {
        await navigator.clipboard.writeText(url);
        toast.success(t("Link copied.", "تم نسخ الرابط."));
      }
    });
  }
  return (
    <article className="post">
      <div className="row">
        <button className="row grow" onClick={() => openProfile(post.author)}>
          <Avatar name={post.name} src={post.avatar} />
          <div className="grow" style={{ textAlign: "start" }}>
            <strong className="small">{post.name}</strong>
            <p className="meta">
              <bdi>@{post.username}</bdi> ·{" "}
              <time dateTime={new Date(post.created).toISOString()}>
                {dateLabel(post.created, language)}
              </time>
            </p>
          </div>
        </button>
        {post.pinned === 1 && (
          <Pin className="ink" aria-label={t("Pinned", "مثبّت")} />
        )}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              className="icon-button"
              aria-label={t("Post actions", "خيارات المنشور")}
            >
              <MoreHorizontal />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            {post.author === user!.id ? (
              <>
                <DropdownMenuItem onSelect={() => setEditing(true)}>
                  {t("Edit post", "تعديل المنشور")}
                </DropdownMenuItem>
                <DropdownMenuItem
                  onSelect={() =>
                    run(async () => {
                      await api("posts/" + post.id, "PATCH", {
                        pinned: post.pinned ? 0 : 1,
                      });
                      bump();
                    })
                  }
                >
                  <Pin />
                  {post.pinned
                    ? t("Unpin", "إلغاء التثبيت")
                    : t("Pin to My Space", "تثبيت في مساحتي")}
                </DropdownMenuItem>
                <DropdownMenuItem onSelect={() => setDeleting(true)}>
                  <Trash2 />
                  {t("Delete", "حذف")}
                </DropdownMenuItem>
              </>
            ) : (
              <>
                <DropdownMenuItem
                  onSelect={() =>
                    run(async () => {
                      await api("posts/" + post.id + "/hide", "POST");
                      bump();
                      onRemoved?.();
                    })
                  }
                >
                  <EyeOff />
                  {t("Show me less like this", "إخفاء وتقليل هذا المحتوى")}
                </DropdownMenuItem>
                <DropdownMenuItem onSelect={() => setReport(true)}>
                  <Flag />
                  {t("Report", "إبلاغ")}
                </DropdownMenuItem>
              </>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
      {post.audience !== "public" && (
        <span className="meta row" style={{ gap: 5, marginTop: 8 }}>
          <Lock width={14} height={14} />
          {post.audience === "only_me"
            ? t("Only you", "أنت فقط")
            : t("Followers", "المتابعون")}
        </span>
      )}
      <div className="post-body" dir="auto">
        {post.body}
      </div>
      {post.image && (
        <button
          className="post-image-button"
          onClick={() => setImage(true)}
          aria-label={t("Open image", "فتح الصورة")}
        >
          <img
            className="post-image"
            src={"/api/media/" + post.image}
            loading="lazy"
            alt={t("Image shared in this post", "صورة مرفقة بالمنشور")}
          />
        </button>
      )}
      {post.song && <SongCard song={post.song} />}
      <div className="post-actions">
        <button
          className={liked ? "active" : ""}
          onClick={like}
          aria-pressed={liked}
          aria-label={t("Like", "إعجاب")}
          disabled={busy}
        >
          <Heart fill={liked ? "currentColor" : "none"} />
          <span>{count > 0 ? count : t("Like", "إعجاب")}</span>
        </button>
        <button
          onClick={() => openPost(post.id)}
          aria-label={t("Comments", "التعليقات")}
        >
          <MessageCircle />
          <span>{post.comments || t("Reply", "رد")}</span>
        </button>
        <button onClick={share} aria-label={t("Share", "مشاركة")}>
          <Upload />
        </button>
        <button
          style={{ marginInlineStart: "auto" }}
          className={post.saved ? "active" : ""}
          onClick={() => setSaved(true)}
          aria-label={t("Save", "حفظ")}
        >
          <Bookmark fill={post.saved ? "currentColor" : "none"} />
        </button>
      </div>
      <Modal
        open={image}
        onClose={() => setImage(false)}
        title={t("Image", "الصورة")}
        className="image-view"
      >
        <img
          src={"/api/media/" + post.image}
          alt={t("Shared image", "الصورة المرفقة")}
        />
      </Modal>
      {saved && <SavePost post={post} onClose={() => setSaved(false)} />}
      <Composer open={editing} onClose={() => setEditing(false)} edit={post} />
      <Confirm
        open={deleting}
        onCancel={() => setDeleting(false)}
        title={t("Delete this post?", "حذف هذا المنشور؟")}
        description={t(
          "Its comments and saved references will also be removed.",
          "ستُحذف التعليقات والإشارات المحفوظة المرتبطة به أيضًا.",
        )}
        onConfirm={() =>
          run(async () => {
            await api("posts/" + post.id, "DELETE");
            bump();
            onRemoved?.();
          })
        }
      />
      {report && (
        <Report kind="post" target={post.id} onClose={() => setReport(false)} />
      )}
    </article>
  );
}
export function FeedList({
  path,
  emptyTitle,
  emptyDescription,
  action,
}: {
  path: string;
  emptyTitle?: string;
  emptyDescription?: string;
  action?: React.ReactNode;
}) {
  const { t, refresh } = useApp();
  const r = useResource<{ items: Post[]; next: Cursor }>(path, {
    items: [],
    next: null,
  });
  const { busy, run } = useAction();
  const [pages, setPages] = useState<Post[]>([]),
    [cursor, setCursor] = useState<Cursor>(null);
  const retained = useRef<Post[]>([]);
  const [removed, setRemoved] = useState<Set<string>>(new Set());
  useEffect(() => {
    retained.current = pages;
  }, [pages]);
  useEffect(() => {
    retained.current = [];
    setPages([]);
    setRemoved(new Set());
  }, [path]);
  useEffect(() => {
    if (!retained.current.length) setCursor(r.data.next);
  }, [r.data.next]);
  useEffect(() => {
    let active = true;
    const snapshot = retained.current;
    if (snapshot.length)
      void Promise.all(
        snapshot.map(async (post) => {
          try {
            return (await api<{ post: Post }>("posts/" + post.id)).post;
          } catch (error) {
            return error instanceof RequestError &&
              [403, 404].includes(error.status)
              ? null
              : post;
          }
        }),
      ).then((posts) => {
        if (active) setPages(posts.filter((p): p is Post => p !== null));
      });
    return () => {
      active = false;
    };
  }, [refresh, path]);
  const items = [...r.data.items, ...pages].filter(
    (p, i, a) => !removed.has(p.id) && a.findIndex((x) => x.id === p.id) === i,
  );
  if (r.loading && !items.length) return <Loading />;
  if (r.error && !items.length)
    return <ErrorState error={r.error} retry={r.reload} />;
  return (
    <>
      {!!r.error && <ErrorState error={r.error} retry={r.reload} />}
      {items.length ? (
        items.map((p) => (
          <PostCard
            key={p.id}
            post={p}
            onRemoved={() => setRemoved((ids) => new Set([...ids, p.id]))}
          />
        ))
      ) : (
        <EmptyState
          icon={<Feather />}
          title={
            emptyTitle ||
            t("A space waiting for a thought.", "مساحة تنتظر فكرة.")
          }
          description={
            emptyDescription ||
            t(
              "There’s nothing here yet. Share something or follow people who interest you.",
              "لا توجد منشورات بعد. شارك شيئًا أو تابع أشخاصًا يثيرون اهتمامك.",
            )
          }
          action={action}
        />
      )}{" "}
      {cursor && (
        <div className="page-content">
          <BusyButton
            busy={busy}
            variant="outline"
            onClick={() =>
              run(async () => {
                const next = await api<{ items: Post[]; next: Cursor }>(
                  path +
                    (path.includes("?") ? "&" : "?") +
                    new URLSearchParams({
                      before: String(cursor.before),
                      cursor: cursor.cursor,
                      score: String(cursor.score ?? 10000),
                    }),
                );
                setPages((p) => [...p, ...next.items]);
                setCursor(next.next);
              })
            }
          >
            {t("Load more", "عرض المزيد")}
          </BusyButton>
        </div>
      )}
    </>
  );
}
type Comment = {
  id: string;
  postId: string;
  author: string;
  parent: string | null;
  body: string;
  created: number;
  name: string;
  username: string;
  avatar: string | null;
};
export function PostDetail({ postId }: { postId: string }) {
  const { t, bump, openProfile } = useApp();
  const r = useResource<{ post: Post }>(
    "posts/" + postId,
    {} as { post: Post },
  );
  const comments = useResource<{ items: Comment[] }>(
    "posts/" + postId + "/comments",
    { items: [] },
  );
  const [body, setBody] = useState(""),
    [parent, setParent] = useState<Comment | null>(null);
  const { busy, run } = useAction();
  const commentId = useRef(crypto.randomUUID());
  const [older, setOlder] = useState<Comment[]>([]);
  useEffect(() => {
    setOlder([]);
  }, [postId]);
  if (r.loading) return <Loading />;
  if (r.error) return <ErrorState error={r.error} retry={r.reload} />;
  return (
    <>
      <PostCard post={r.data.post} detail />
      <div className="stack" style={{ paddingTop: 20 }}>
        <h2>{t("Conversation", "النقاش")}</h2>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            void run(async () => {
              await api("posts/" + postId + "/comments", "POST", {
                id: commentId.current,
                body,
                parent: parent?.id || null,
              });
              commentId.current = crypto.randomUUID();
              setBody("");
              setParent(null);
              bump();
            });
          }}
          className="stack"
        >
          {parent && (
            <div className="row between alert">
              <span>
                {t("Replying to", "ردًا على")} {parent.name}
              </span>
              <IconButton
                label={t("Cancel reply", "إلغاء الرد")}
                onClick={() => setParent(null)}
              >
                <X />
              </IconButton>
            </div>
          )}
          <Textarea
            dir="auto"
            value={body}
            onChange={(e) => setBody(e.target.value)}
            maxLength={1000}
            placeholder={t("Add to the conversation…", "شارك في النقاش…")}
            aria-label={t("Comment", "تعليق")}
          />
          <BusyButton busy={busy} disabled={!body.trim()} type="submit">
            {t("Reply", "رد")}
            <Send />
          </BusyButton>
        </form>
        {comments.error ? (
          <ErrorState error={comments.error} retry={comments.reload} />
        ) : comments.loading ? (
          <Loading />
        ) : (
          [...comments.data.items, ...older].map((cm) => (
            <div
              key={cm.id}
              className="thread-comment"
              style={{ marginInlineStart: cm.parent ? 20 : 0 }}
            >
              <button className="row" onClick={() => openProfile(cm.author)}>
                <Avatar name={cm.name} src={cm.avatar} />
                <strong className="small">{cm.name}</strong>
              </button>
              {cm.parent && (
                <span className="meta">
                  {t("Threaded reply", "رد ضمن المحادثة")}
                </span>
              )}
              <p className="post-body" dir="auto">
                {cm.body}
              </p>
              <button className="small ink" onClick={() => setParent(cm)}>
                {t("Reply", "رد")}
              </button>
            </div>
          ))
        )}
        {comments.data.items.length === 40 && (
          <Button
            variant="ghost"
            disabled={busy}
            onClick={() =>
              run(async () => {
                const before = (older.at(-1) || comments.data.items.at(-1))!
                  .created;
                const page = await api<{ items: Comment[] }>(
                  "posts/" + postId + "/comments?before=" + before,
                );
                setOlder((o) => [...o, ...page.items]);
              })
            }
          >
            {t("Older replies", "ردود أقدم")}
          </Button>
        )}
      </div>
    </>
  );
}
export function Moments({ onCreate }: { onCreate: () => void }) {
  const { t, openChat, user } = useApp();
  const r = useResource<{ items: Post[] }>("feed?kind=moment", { items: [] });
  const reloadMoments = r.reload;
  const [clock, setClock] = useState(() => Date.now());
  const [selected, setSelected] = useState<Post | null>(null),
    [deleting, setDeleting] = useState(false);
  const { run, busy } = useAction();
  useEffect(() => {
    const timer = setInterval(() => {
      setClock(Date.now());
      reloadMoments();
    }, 30000);
    return () => clearInterval(timer);
  }, [reloadMoments]);
  return (
    <>
      <div className="moments">
        <button className="moment" onClick={onCreate}>
          <span className="moment-ring moment-add">
            <Plus />
          </span>
          <span>{t("Your moment", "لحظتك")}</span>
        </button>
        {r.data.items
          .filter((p) => !p.expires || p.expires > clock)
          .map((p) => (
            <button
              className="moment"
              key={p.id}
              onClick={() => setSelected(p)}
            >
              <span className="moment-ring">
                <Avatar name={p.name} src={p.avatar} />
              </span>
              <span>{p.name.split(" ")[0]}</span>
            </button>
          ))}
      </div>
      {selected && (
        <Modal open title={selected.name} onClose={() => setSelected(null)}>
          <div className="stack">
            {selected.expires && selected.expires <= clock ? (
              <p>{t("This Moment has expired.", "انتهت صلاحية هذه اللحظة.")}</p>
            ) : (
              <>
                <p className="meta">
                  {selected.mood} ·{" "}
                  {t("Disappears after 24 hours", "تختفي بعد 24 ساعة")}
                </p>
                <p dir="auto">{selected.body}</p>
                {selected.image && (
                  <img
                    className="post-image"
                    src={"/api/media/" + selected.image}
                    alt={t("Moment image", "صورة اللحظة")}
                  />
                )}{" "}
                {selected.song && <SongCard song={selected.song} />}{" "}
                {selected.author === user!.id ? (
                  <Button variant="outline" onClick={() => setDeleting(true)}>
                    {t("Delete Moment", "حذف اللحظة")}
                  </Button>
                ) : (
                  <BusyButton
                    busy={busy}
                    onClick={() =>
                      run(async () => {
                        const data = await api<{
                          conversation: { id: string };
                        }>("conversations", "POST", {
                          userId: selected.author,
                        });
                        setSelected(null);
                        openChat(data.conversation.id);
                      })
                    }
                  >
                    {t("Reply privately", "رد برسالة خاصة")}
                    <MessageCircle />
                  </BusyButton>
                )}
              </>
            )}
          </div>
        </Modal>
      )}
      <Confirm
        open={deleting}
        title={t("Delete this Moment?", "حذف هذه اللحظة؟")}
        description={t(
          "It will no longer be visible.",
          "لن تبقى هذه اللحظة ظاهرة.",
        )}
        onCancel={() => setDeleting(false)}
        onConfirm={() =>
          run(async () => {
            await api("posts/" + selected!.id, "DELETE");
            setSelected(null);
            setDeleting(false);
            r.reload();
          })
        }
      />
    </>
  );
}
