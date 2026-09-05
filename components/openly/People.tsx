/* eslint-disable react-hooks/set-state-in-effect -- Effects hydrate external session, network, and device draft state; updates are bounded by resource identity. */
"use client";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import type { Circle, Song, User } from "@/shared/types";
import {
  Bookmark,
  Flag,
  Lock,
  LogOut,
  MessageCircle,
  Music2,
  Plus,
  Search,
  Settings,
  Trash2,
  Users,
  X,
} from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { CircleRow } from "./Circles";
import {
  api,
  errorText,
  imageUpload,
  interestLabels,
  useAction,
  useApp,
  useResource,
} from "./context";
import { FeedList, Report, SongPicker } from "./Posts";
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
export function PersonRow({ person }: { person: User }) {
  const { t, openProfile, bump } = useApp();
  const { busy, run } = useAction();
  const names = person.shared?.map((i) => t(...(interestLabels[i] || [i, i])));
  return (
    <div className="person-row">
      <button
        className="row grow"
        onClick={() => openProfile(person.id)}
        style={{ textAlign: "start" }}
      >
        <Avatar name={person.name} src={person.avatar} />
        <span className="grow">
          <strong className="small">{person.name}</strong>
          <p className="meta">
            <bdi>@{person.username}</bdi>
          </p>
          {!!names?.length && (
            <p className="meta ink">
              {t("You both enjoy ", "يجمعكما الاهتمام بـ ") +
                names.slice(0, 2).join(t(" and ", " و"))}
            </p>
          )}
        </span>
      </button>
      <BusyButton
        busy={busy}
        variant={person.following ? "outline" : "secondary"}
        onClick={() =>
          run(async () => {
            await api(
              "people/" + person.id + "/follow",
              person.following ? "DELETE" : "POST",
            );
            bump();
          })
        }
      >
        {person.following === "pending"
          ? t("Requested", "تم الطلب")
          : person.following
            ? t("Following", "تتابعه")
            : t("Follow", "متابعة")}
      </BusyButton>
    </div>
  );
}
export function Discover({ openCircle }: { openCircle: (id: string) => void }) {
  const { t, user } = useApp();
  const [query, setQuery] = useState(""),
    [term, setTerm] = useState(""),
    [filter, setFilter] = useState("people"),
    [recent, setRecent] = useState<string[]>([]);
  useEffect(() => {
    try {
      setRecent(
        JSON.parse(
          localStorage.getItem("openly:" + user!.id + ":recent") || "[]",
        ),
      );
    } catch {}
  }, [user]);
  useEffect(() => {
    const timer = setTimeout(() => setTerm(query), 350);
    return () => clearTimeout(timer);
  }, [query]);
  const people = useResource<{ items: User[] }>(
    filter === "people" ? "people?q=" + encodeURIComponent(term) : null,
    { items: [] },
  );
  const circles = useResource<{ items: Circle[] }>(
    filter === "circles" ? "circles?q=" + encodeURIComponent(term) : null,
    { items: [] },
  );
  const songs = useResource<{ items: Song[] }>(
    filter === "songs" && term.length > 1
      ? "music?q=" + encodeURIComponent(term)
      : null,
    { items: [] },
  );
  function remember() {
    const next = [query.trim(), ...recent.filter((x) => x !== query.trim())]
      .filter(Boolean)
      .slice(0, 6);
    setRecent(next);
    localStorage.setItem(
      "openly:" + user!.id + ":recent",
      JSON.stringify(next),
    );
  }
  return (
    <>
      <div className="page-content stack">
        <form
          onSubmit={(e) => {
            e.preventDefault();
            setTerm(query);
            remember();
          }}
          className="searchbox"
        >
          <Search aria-hidden="true" />
          <Input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onBlur={remember}
            placeholder={t(
              "People, thoughts, songs, Circles…",
              "أشخاص، أفكار، أغاني، دوائر…",
            )}
            aria-label={t("Search Openly", "البحث في Openly")}
          />
          {query && (
            <IconButton
              label={t("Clear search", "مسح البحث")}
              onClick={() => {
                setQuery("");
                setTerm("");
              }}
            >
              <X />
            </IconButton>
          )}
        </form>
        <Tabs
          value={filter}
          onValueChange={setFilter}
          dir={user?.language === "ar" ? "rtl" : "ltr"}
        >
          <TabsList variant="line" className="w-full justify-between">
            {[
              ["people", t("People", "أشخاص")],
              ["posts", t("Posts", "منشورات")],
              ["songs", t("Songs", "أغانٍ")],
              ["circles", t("Circles", "دوائر")],
            ].map(([key, label]) => (
              <TabsTrigger value={key} key={key}>
                {label}
              </TabsTrigger>
            ))}
          </TabsList>
        </Tabs>
        {!query && recent.length > 0 && (
          <div className="row wrap">
            {recent.map((x) => (
              <button className="pill" key={x} onClick={() => setQuery(x)}>
                {x}
              </button>
            ))}
            <button
              className="meta"
              onClick={() => {
                setRecent([]);
                localStorage.removeItem("openly:" + user!.id + ":recent");
              }}
            >
              {t("Clear recent", "مسح السجل")}
            </button>
          </div>
        )}
        {!query && filter === "people" && (
          <div>
            <span className="eyebrow">
              {t("A little common ground", "اهتمامات تجمعكما")}
            </span>
            <p className="small muted" style={{ marginTop: 8 }}>
              {t(
                "Discover people through the things you love.",
                "اكتشف أشخاصًا من خلال الأشياء التي تحبها.",
              )}
            </p>
          </div>
        )}
        {filter === "people" &&
          (people.loading ? (
            <Loading />
          ) : people.error ? (
            <ErrorState error={people.error} retry={people.reload} />
          ) : people.data.items.length ? (
            people.data.items.map((p) => <PersonRow key={p.id} person={p} />)
          ) : (
            <EmptyState
              icon={<Users />}
              title={t(
                "Your people will find their way here.",
                "هنا ستجد أشخاصًا يشبهونك.",
              )}
              description={
                query
                  ? t(
                      "No matching people. Try another name.",
                      "لا توجد نتائج مطابقة. جرّب اسمًا آخر.",
                    )
                  : t(
                      "There are no other accounts to suggest yet. Invite someone to join Openly.",
                      "لا توجد حسابات أخرى لاقتراحها بعد. ادعُ شخصًا للانضمام إلى Openly.",
                    )
              }
            />
          ))}
        {filter === "circles" &&
          (circles.loading ? (
            <Loading />
          ) : circles.error ? (
            <ErrorState error={circles.error} retry={circles.reload} />
          ) : circles.data.items.length ? (
            circles.data.items.map((c) => (
              <CircleRow
                key={c.id}
                circle={c}
                onOpen={() => openCircle(c.id)}
              />
            ))
          ) : (
            <EmptyState
              title={t("No matching Circles.", "لا توجد دوائر مطابقة.")}
              description={t(
                "Try a different search, or start a Circle of your own.",
                "جرّب بحثًا آخر أو ابدأ دائرتك.",
              )}
            />
          ))}
        {filter === "songs" &&
          (songs.loading ? (
            <Loading />
          ) : songs.error ? (
            <ErrorState error={songs.error} retry={songs.reload} />
          ) : songs.data.items.length ? (
            songs.data.items.map((s) => <SongCard song={s} key={s.id} />)
          ) : (
            <EmptyState
              icon={<Music2 />}
              title={t(
                "Find the song that says it.",
                "اعثر على أغنية تعبّر عنك.",
              )}
              description={t(
                "Search for a song or artist. Previews play only when you choose.",
                "ابحث عن أغنية أو فنان. المقتطفات تعمل فقط باختيارك.",
              )}
            />
          ))}
      </div>
      {filter === "posts" && (
        <FeedList path={"search?q=" + encodeURIComponent(term)} />
      )}
    </>
  );
}
export function Profile({
  id,
  onSettings,
}: {
  id: string;
  onSettings?: () => void;
}) {
  const { user, t, bump, openChat } = useApp();
  const [edit, setEdit] = useState(false),
    [saved, setSaved] = useState(false),
    [report, setReport] = useState(false),
    [block, setBlock] = useState(false);
  const { busy, run } = useAction();
  const r = useResource<{ user: User }>("people/" + id, {} as { user: User });
  if (r.loading) return <Loading />;
  if (r.error) return <ErrorState error={r.error} retry={r.reload} />;
  const person = r.data.user;
  const own = person.id === user!.id;
  return (
    <>
      <div
        className="cover"
        style={{
          background:
            person.accent === "indigo"
              ? "#dfe3f6"
              : person.accent === "slate"
                ? "#dce4ed"
                : undefined,
        }}
      />
      <div className="profile-head">
        <div className="row between">
          <Avatar large name={person.name} src={person.avatar} />
          <div className="row" style={{ marginTop: 40 }}>
            {own ? (
              <>
                <Button variant="outline" onClick={() => setEdit(true)}>
                  {t("Edit profile", "تعديل الملف")}
                </Button>
                <IconButton
                  label={t("Settings", "الإعدادات")}
                  onClick={onSettings}
                >
                  <Settings />
                </IconButton>
              </>
            ) : (
              <>
                <BusyButton
                  busy={busy}
                  onClick={() =>
                    run(async () => {
                      await api(
                        "people/" + person.id + "/follow",
                        person.following ? "DELETE" : "POST",
                      );
                      bump();
                    })
                  }
                >
                  {person.following === "pending"
                    ? t("Requested", "تم الطلب")
                    : person.following
                      ? t("Following", "تتابعه")
                      : t("Follow", "متابعة")}
                </BusyButton>
                <IconButton
                  label={t("Message", "رسالة")}
                  disabled={busy}
                  onClick={() =>
                    run(async () => {
                      const d = await api<{ conversation: { id: string } }>(
                        "conversations",
                        "POST",
                        { userId: person.id },
                      );
                      openChat(d.conversation.id);
                    })
                  }
                >
                  <MessageCircle />
                </IconButton>
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <button
                      className="icon-button"
                      aria-label={t("Privacy actions", "خيارات الخصوصية")}
                    >
                      <Flag />
                    </button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent>
                    <DropdownMenuItem onSelect={() => setReport(true)}>
                      {t("Report profile", "الإبلاغ عن الملف")}
                    </DropdownMenuItem>
                    <DropdownMenuItem onSelect={() => setBlock(true)}>
                      {t("Block account", "حظر الحساب")}
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              </>
            )}
          </div>
        </div>
        <div className="row" style={{ marginTop: 12 }}>
          <h1>{person.name}</h1>
          {person.private === 1 && (
            <Lock aria-label={t("Private account", "حساب خاص")} />
          )}
        </div>
        <p className="meta">
          <bdi>@{person.username}</bdi> ·{" "}
          {new Intl.NumberFormat(user?.language).format(person.followers || 0)}{" "}
          {t("followers", "متابع")}
        </p>
        {person.bio && (
          <p className="bio" dir="auto">
            {person.bio}
          </p>
        )}
        <div className="row wrap" style={{ marginTop: 15 }}>
          {person.interests.map((i) => (
            <span className="pill" key={i}>
              {interestLabels[i] ? t(...interestLabels[i]) : i}
            </span>
          ))}
        </div>
        {person.song && (
          <>
            <span className="eyebrow block mt-5">
              {t("On repeat lately", "أستمع إليها هذه الأيام")}
            </span>
            <SongCard song={person.song} />
          </>
        )}
        {own && (
          <Button
            variant="ghost"
            className="mt-4"
            onClick={() => setSaved(true)}
          >
            <Bookmark />
            {t("Private collections", "المجموعات الخاصة")}
            <Lock />
          </Button>
        )}
      </div>
      <div className="feed-label">
        <span>{t("Thoughts & shares", "أفكار ومشاركات")}</span>
      </div>
      <FeedList
        path={"feed?author=" + person.id}
        emptyTitle={
          person.private && !own && !person.following
            ? t("A private space.", "مساحة خاصة.")
            : undefined
        }
        emptyDescription={
          person.private && !own && !person.following
            ? t(
                "Request to follow this person to see their posts.",
                "أرسل طلب متابعة لتتمكن من رؤية المنشورات.",
              )
            : undefined
        }
      />
      {edit && <EditProfile onClose={() => setEdit(false)} />}{" "}
      {saved && <Collections onClose={() => setSaved(false)} />}{" "}
      {report && (
        <Report
          kind="person"
          target={person.id}
          onClose={() => setReport(false)}
        />
      )}
      <Confirm
        open={block}
        onCancel={() => setBlock(false)}
        title={t("Block this account?", "حظر هذا الحساب؟")}
        description={t(
          "You won’t see each other’s content or be able to message.",
          "لن يرى أي منكما محتوى الآخر ولن تتمكنا من المراسلة.",
        )}
        onConfirm={() =>
          run(async () => {
            await api("people/" + person.id + "/block", "POST");
            setBlock(false);
            bump();
          })
        }
      />
    </>
  );
}
function EditProfile({ onClose }: { onClose: () => void }) {
  const { user, setUser, t, bump, language } = useApp();
  const [name, setName] = useState(user!.name),
    [bio, setBio] = useState(user!.bio),
    [interests, setInterests] = useState(user!.interests),
    [song, setSong] = useState(user!.song),
    [accent, setAccent] = useState(user!.accent),
    [avatar, setAvatar] = useState(user!.avatar),
    [music, setMusic] = useState(false),
    [uploading, setUploading] = useState(false);
  const { busy, run } = useAction();
  return (
    <>
      <Modal
        open
        title={t("Edit your space", "تعديل مساحتك")}
        onClose={onClose}
      >
        <form
          className="form-grid"
          onSubmit={(e) => {
            e.preventDefault();
            void run(async () => {
              const d = await api<{ user: User }>("me", "PATCH", {
                name,
                bio,
                interests,
                song,
                accent,
                avatar,
              });
              setUser(d.user);
              bump();
              onClose();
            });
          }}
        >
          <label>
            {t("Display name", "الاسم")}
            <Input
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
              maxLength={60}
            />
          </label>
          <label>
            {t("Bio", "نبذة")}
            <Textarea
              dir="auto"
              value={bio}
              onChange={(e) => setBio(e.target.value)}
              maxLength={300}
            />
          </label>
          <label>
            {t("Profile photo", "الصورة الشخصية")}
            <Input
              type="file"
              accept="image/*"
              onChange={async (e) => {
                if (!e.target.files?.[0]) return;
                setUploading(true);
                try {
                  setAvatar((await imageUpload(e.target.files[0])).id);
                } catch (e) {
                  toast.error(errorText(e, language));
                } finally {
                  setUploading(false);
                }
              }}
            />
          </label>
          <div className="row wrap">
            {Object.entries(interestLabels).map(([key, names]) => (
              <button
                type="button"
                key={key}
                className={
                  "pill " + (interests.includes(key) ? "selected" : "")
                }
                onClick={() =>
                  setInterests((x) =>
                    x.includes(key) ? x.filter((i) => i !== key) : [...x, key],
                  )
                }
                aria-pressed={interests.includes(key)}
              >
                {t(...names)}
              </button>
            ))}
          </div>
          <Choice
            value={accent}
            onChange={setAccent}
            label={t("Cover accent", "لون الغلاف")}
            options={[
              ["blue", t("Ink blue", "أزرق الحبر")],
              ["indigo", t("Indigo", "نيلي")],
              ["slate", t("Slate", "رمادي أزرق")],
            ]}
          />
          {song && <SongCard song={song} />}
          <div className="row">
            <Button
              type="button"
              variant="outline"
              onClick={() => setMusic(true)}
            >
              <Music2 />
              {t("Featured song", "الأغنية المميزة")}
            </Button>
            {song && (
              <Button
                type="button"
                variant="ghost"
                onClick={() => setSong(null)}
              >
                {t("Remove", "إزالة")}
              </Button>
            )}
          </div>
          <BusyButton type="submit" busy={busy || uploading}>
            {t("Save changes", "حفظ التغييرات")}
          </BusyButton>
        </form>
      </Modal>
      <SongPicker
        open={music}
        onClose={() => setMusic(false)}
        onPick={setSong}
      />
    </>
  );
}
export function Collections({ onClose }: { onClose: () => void }) {
  const { t, bump } = useApp();
  const r = useResource<{
    items: { id: string; name: string; count: number }[];
  }>("collections", { items: [] });
  const [selected, setSelected] = useState<string | null>(null),
    [rename, setRename] = useState<{ id: string; name: string } | null>(null),
    [remove, setRemove] = useState<string | null>(null),
    [name, setName] = useState("");
  const { busy, run } = useAction();
  return (
    <>
      <Modal
        open
        title={t("Private collections", "المجموعات الخاصة")}
        onClose={onClose}
        description={t(
          "Only you can access these saved posts.",
          "لا يمكن لأي شخص آخر الوصول إلى هذه المنشورات المحفوظة.",
        )}
      >
        <div className="stack">
          {selected ? (
            <>
              <Button variant="ghost" onClick={() => setSelected(null)}>
                {t("All collections", "كل المجموعات")}
              </Button>
              <FeedList path={"collections/" + selected} />
            </>
          ) : (
            <>
              {r.loading ? (
                <Loading />
              ) : r.error ? (
                <ErrorState error={r.error} retry={r.reload} />
              ) : (
                r.data.items.map((c) => (
                  <div className="row between" key={c.id}>
                    <button
                      className="row grow"
                      onClick={() => setSelected(c.id)}
                    >
                      <Bookmark />
                      <span>
                        {c.name} <span className="meta">({c.count})</span>
                      </span>
                    </button>
                    <Button
                      variant="ghost"
                      onClick={() => setRename({ id: c.id, name: c.name })}
                    >
                      {t("Rename", "تسمية")}
                    </Button>
                    <IconButton
                      label={t("Delete collection", "حذف المجموعة")}
                      onClick={() => setRemove(c.id)}
                    >
                      <Trash2 />
                    </IconButton>
                  </div>
                ))
              )}
              <form
                className="row"
                onSubmit={(e) => {
                  e.preventDefault();
                  void run(async () => {
                    await api("collections", "POST", { name });
                    setName("");
                    r.reload();
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
                <BusyButton busy={busy} type="submit">
                  <Plus />
                </BusyButton>
              </form>
            </>
          )}
        </div>
      </Modal>
      <Modal
        open={!!rename}
        title={t("Rename collection", "تسمية المجموعة")}
        onClose={() => setRename(null)}
      >
        <div className="stack">
          <Input
            value={rename?.name || ""}
            onChange={(e) =>
              setRename((x) => (x ? { ...x, name: e.target.value } : null))
            }
            aria-label={t("Name", "الاسم")}
          />
          <BusyButton
            busy={busy}
            disabled={!rename?.name.trim()}
            onClick={() =>
              run(async () => {
                await api("collections/" + rename!.id, "PATCH", {
                  name: rename!.name,
                });
                setRename(null);
                r.reload();
              })
            }
          >
            {t("Save", "حفظ")}
          </BusyButton>
        </div>
      </Modal>
      <Confirm
        open={!!remove}
        title={t("Delete collection?", "حذف المجموعة؟")}
        description={t(
          "The original posts will still exist.",
          "ستبقى المنشورات الأصلية موجودة.",
        )}
        onCancel={() => setRemove(null)}
        onConfirm={() =>
          run(async () => {
            await api("collections/" + remove, "DELETE");
            setRemove(null);
            r.reload();
            bump();
          })
        }
      />
    </>
  );
}
export function SettingsPanel({ onClose }: { onClose: () => void }) {
  const { t, user, setUser, setLanguage, bump } = useApp();
  const { busy, run } = useAction();
  const [deleting, setDeleting] = useState(false);
  const blocks = useResource<{ items: User[] }>("blocks", { items: [] });
  async function change(value: Record<string, unknown>) {
    await run(async () => {
      const d = await api<{ user: User }>("me", "PATCH", value);
      setUser(d.user);
      if (value.language) setLanguage(value.language as "ar" | "en");
      bump();
    });
  }
  return (
    <>
      <Modal open title={t("Settings", "الإعدادات")} onClose={onClose}>
        <div className="stack">
          <h3>{t("Your preferences", "تفضيلاتك")}</h3>
          <div className="settings-row">
            <span>{t("Language", "اللغة")}</span>
            <Choice
              value={user!.language || "en"}
              onChange={(language) => change({ language })}
              label={t("Language", "اللغة")}
              options={[
                ["en", "English"],
                ["ar", "العربية"],
              ]}
            />
          </div>
          <div className="settings-row">
            <span>{t("Appearance", "المظهر")}</span>
            <Choice
              value={user!.theme || "system"}
              onChange={(theme) => change({ theme })}
              label={t("Appearance", "المظهر")}
              options={[
                ["system", t("System", "النظام")],
                ["light", t("Light", "فاتح")],
                ["dark", t("Dark", "داكن")],
              ]}
            />
          </div>
          <h3>{t("Privacy & safety", "الخصوصية والأمان")}</h3>
          {[
            [
              "private",
              t("Private account", "حساب خاص"),
              t("Approve who follows you.", "وافق على من يتابعك."),
            ],
            [
              "receipts",
              t("Read receipts", "إيصالات القراءة"),
              t(
                "Let people know when you read a message.",
                "أخبر الآخرين عند قراءة رسائلهم.",
              ),
            ],
            [
              "activity",
              t("Activity visibility", "ظهور النشاط"),
              t("Share your typing indicator.", "مشاركة مؤشر الكتابة."),
            ],
          ].map(([key, label, help]) => (
            <div className="settings-row" key={key}>
              <div>
                <strong className="small">{label}</strong>
                <p>{help}</p>
              </div>
              <Switch
                aria-label={label}
                checked={!!user![key as keyof User]}
                onCheckedChange={(v) => change({ [key]: v ? 1 : 0 })}
                disabled={busy}
              />
            </div>
          ))}
          <div className="settings-row">
            <span className="small">
              {t("Who can message you", "من يستطيع مراسلتك")}
            </span>
            <Choice
              value={user!.messages || "requests"}
              onChange={(messages) => change({ messages })}
              label={t("Messaging permissions", "صلاحيات المراسلة")}
              options={[
                ["everyone", t("Everyone", "الجميع")],
                ["requests", t("Message requests", "طلبات رسائل")],
                ["following", t("People I follow", "من أتابعهم")],
                ["nobody", t("Nobody", "لا أحد")],
              ]}
            />
          </div>
          <h3>{t("Notifications", "الإشعارات")}</h3>
          {[
            ["like", t("Reactions", "التفاعلات")],
            ["comment", t("Replies", "الردود")],
            ["follow", t("New followers", "متابعون جدد")],
            ["follow_request", t("Follow requests", "طلبات المتابعة")],
            ["message_request", t("Message requests", "طلبات الرسائل")],
            ["message", t("Messages", "الرسائل")],
          ].map(([key, label]) => (
            <div className="settings-row" key={key}>
              <span className="small">{label}</span>
              <Switch
                aria-label={label}
                disabled={busy}
                checked={user!.notifications?.includes(key)}
                onCheckedChange={(v) =>
                  change({
                    notifications: v
                      ? [...(user!.notifications || []), key]
                      : (user!.notifications || []).filter((x) => x !== key),
                  })
                }
              />
            </div>
          ))}
          <p className="meta">
            {t(
              "These controls apply to your notification center. iPhone push becomes available after the app’s push service is configured.",
              "تتحكم هذه الإعدادات بمركز الإشعارات. تتوفر إشعارات iPhone بعد تفعيل خدمة الإشعارات الخاصة بالتطبيق.",
            )}
          </p>
          <h3>{t("Blocked accounts", "الحسابات المحظورة")}</h3>
          {blocks.data.items.length ? (
            blocks.data.items.map((u) => (
              <div className="row between" key={u.id}>
                <span>{u.name}</span>
                <Button
                  variant="outline"
                  disabled={busy}
                  onClick={() =>
                    run(async () => {
                      await api("blocks/" + u.id, "DELETE");
                      blocks.reload();
                      bump();
                    })
                  }
                >
                  {t("Unblock", "إلغاء الحظر")}
                </Button>
              </div>
            ))
          ) : (
            <p className="meta">
              {t("No blocked accounts.", "لا توجد حسابات محظورة.")}
            </p>
          )}
          <div className="divider" />
          <Button
            variant="outline"
            disabled={busy}
            onClick={() =>
              run(async () => {
                await api("auth/logout", "POST");
                setUser(null);
                onClose();
              })
            }
          >
            <LogOut />
            {t("Sign out", "تسجيل الخروج")}
          </Button>
          <Button
            variant="ghost"
            className="error"
            onClick={() => setDeleting(true)}
          >
            {t("Delete my account", "حذف حسابي")}
          </Button>
        </div>
      </Modal>
      <Confirm
        open={deleting}
        title={t("Permanently delete your account?", "حذف حسابك نهائيًا؟")}
        description={t(
          "Your profile, posts, messages, and saved collections will be deleted. This cannot be undone.",
          "سيُحذف ملفك ومنشوراتك ورسائلك ومجموعاتك المحفوظة. لا يمكن التراجع عن ذلك.",
        )}
        onCancel={() => setDeleting(false)}
        onConfirm={() =>
          run(async () => {
            await api("me", "DELETE");
            setUser(null);
            onClose();
          })
        }
      />
    </>
  );
}
