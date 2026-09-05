/* eslint-disable react-hooks/set-state-in-effect -- Effects hydrate external session, network, and device draft state; updates are bounded by resource identity. */
"use client";
import { Sidebar, SidebarProvider } from "@/components/ui/sidebar";
import { Toaster } from "@/components/ui/sonner";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import type { Notice, User } from "@/shared/types";
import {
  ArrowRight,
  ArrowUpRight,
  Bell,
  Bookmark,
  Check,
  Feather,
  Home,
  Lock,
  MessageCircle,
  Music2,
  Search,
  Settings,
  UserRound,
  Users,
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Auth, Onboarding } from "./Auth";
import { Messages } from "./Chat";
import { Circles } from "./Circles";
import type { Language } from "./context";
import {
  AppContext,
  api,
  interestLabels,
  useAction,
  useApp,
  useResource,
} from "./context";
import {
  Collections,
  Discover,
  PersonRow,
  Profile,
  SettingsPanel,
} from "./People";
import { Composer, FeedList, Moments, PostDetail } from "./Posts";
import {
  Avatar,
  Brand,
  Button,
  Choice,
  EmptyState,
  ErrorState,
  IconButton,
  Loading,
  Modal,
  Panel,
} from "./primitives";
const destinations = [
  { id: "home", icon: Home, en: "Home", ar: "الرئيسية" },
  { id: "discover", icon: Search, en: "Discover", ar: "اكتشف" },
  { id: "circles", icon: Users, en: "Circles", ar: "دوائر" },
  { id: "messages", icon: MessageCircle, en: "Messages", ar: "الرسائل" },
  { id: "space", icon: UserRound, en: "My Space", ar: "مساحتي" },
];
export default function Openly() {
  const [user, setUser] = useState<User | null>(null),
    [language, setLang] = useState<Language>("en"),
    [loading, setLoading] = useState(true),
    [loadError, setLoadError] = useState<unknown>(null),
    [refresh, setRefresh] = useState(0),
    [tab, setTab] = useState("home"),
    [profile, setProfile] = useState<string | null>(null),
    [post, setPost] = useState<string | null>(null),
    [chat, setChat] = useState<string | null>(null),
    [circle, setCircle] = useState<string | null>(null);
  const t = useCallback(
    (en: string, ar: string) => (language === "ar" ? ar : en),
    [language],
  );
  const bump = useCallback(() => setRefresh((v) => v + 1), []);
  const setLanguage = useCallback((v: Language) => {
    setLang(v);
    localStorage.setItem("openly:language", v);
  }, []);
  const load = useCallback(() => {
    setLoading(true);
    api<{ user: User }>("me")
      .then((d) => {
        setUser(d.user);
        setLang(d.user.language || "en");
        setLoadError(null);
      })
      .catch((e) => {
        if (e.status === 401) {
          setUser(null);
          setLoadError(null);
        } else setLoadError(e);
      })
      .finally(() => setLoading(false));
  }, []);
  useEffect(() => {
    const lang = localStorage.getItem("openly:language");
    setLang(
      lang === "ar" || (!lang && navigator.language.startsWith("ar"))
        ? "ar"
        : "en",
    );
    load();
  }, [load]);
  useEffect(() => {
    document.documentElement.lang = language;
    document.documentElement.dir = language === "ar" ? "rtl" : "ltr";
  }, [language]);
  useEffect(() => {
    const media = matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      const pref = user?.theme || "system";
      document.documentElement.dataset.theme =
        pref === "system" ? (media.matches ? "dark" : "light") : pref;
    };
    apply();
    media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, [user?.theme]);
  useEffect(() => {
    const viewport = window.visualViewport;
    const resize = () => {
      const keyboard = !!viewport && window.innerHeight - viewport.height > 130;
      document.body.classList.toggle("keyboard-open", keyboard);
      document.documentElement.style.setProperty(
        "--visual-height",
        (viewport?.height || window.innerHeight) + "px",
      );
    };
    viewport?.addEventListener("resize", resize);
    return () => viewport?.removeEventListener("resize", resize);
  }, []);
  useEffect(() => {
    const parse = () => {
      const params = new URLSearchParams(location.search);
      setPost(params.get("post"));
      setProfile(params.get("profile"));
      if (params.get("conversation")) {
        setChat(params.get("conversation"));
        setTab("messages");
      }
    };
    parse();
    window.addEventListener("popstate", parse);
    return () => window.removeEventListener("popstate", parse);
  }, []);
  function openProfile(id: string) {
    setProfile(id);
    history.pushState({}, "", "?profile=" + id);
  }
  function openPost(id: string) {
    setPost(id);
    history.pushState({}, "", "?post=" + id);
  }
  function openChat(id: string) {
    setProfile(null);
    setPost(null);
    setChat(id);
    setTab("messages");
    history.pushState({}, "", "?conversation=" + id);
  }
  function closeOverlays() {
    setProfile(null);
    setPost(null);
    history.replaceState({}, "", location.pathname);
  }
  return (
    <AppContext.Provider
      value={{
        user,
        setUser,
        language,
        setLanguage,
        t,
        refresh,
        bump,
        openProfile,
        openPost,
        openChat,
      }}
    >
      <Toaster position="top-center" richColors />
      {loading ? (
        <main className="onboard">
          <Brand />
          <Loading />
        </main>
      ) : loadError ? (
        <main className="onboard">
          <Brand />
          <ErrorState error={loadError} retry={load} />
        </main>
      ) : !user ? (
        <Auth />
      ) : !user.onboarded ? (
        <Onboarding />
      ) : (
        <>
          <Main
            tab={tab}
            setTab={setTab}
            chat={chat}
            setChat={setChat}
            circle={circle}
            setCircle={setCircle}
          />
          <Panel
            title={t("My Space", "مساحة شخصية")}
            open={!!profile}
            onClose={closeOverlays}
          >
            {profile && <Profile id={profile} />}
          </Panel>
          <Panel
            title={t("A thought & a conversation", "فكرة ونقاش")}
            open={!!post}
            onClose={closeOverlays}
          >
            {post && <PostDetail postId={post} />}
          </Panel>
        </>
      )}
    </AppContext.Provider>
  );
}
function Main({
  tab,
  setTab,
  chat,
  setChat,
  circle,
  setCircle,
}: {
  tab: string;
  setTab: (t: string) => void;
  chat: string | null;
  setChat: (id: string | null) => void;
  circle: string | null;
  setCircle: (id: string | null) => void;
}) {
  const { t, user, language } = useApp();
  const [compose, setCompose] = useState(false),
    [moment, setMoment] = useState(false),
    [notifications, setNotifications] = useState(false),
    [settings, setSettings] = useState(false),
    [collections, setCollections] = useState(false),
    [mode, setMode] = useState("for-you"),
    [sort, setSort] = useState("relevant"),
    [online, setOnline] = useState(true);
  const notice = useResource<{ items: Notice[] }>("notifications", {
    items: [],
  });
  const suggested = useResource<{ items: User[] }>("people", { items: [] });
  const title = destinations.find((x) => x.id === tab)!;
  useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    update();
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => {
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, []);
  useEffect(() => {
    const timer = setInterval(notice.reload, 15000);
    return () => clearInterval(timer);
  }, [notice.reload]);
  function navigate(id: string) {
    (document.activeElement as HTMLElement)?.blur();
    setTab(id);
  }
  return (
    <SidebarProvider className="shell">
      <Sidebar collapsible="none" className="rail">
        <button onClick={() => navigate("home")} aria-label="Openly">
          <Brand />
        </button>
        <nav
          className="nav-list"
          aria-label={t("Main navigation", "التنقل الرئيسي")}
        >
          {destinations.map(({ id, en, ar, icon: Icon }) => (
            <button
              key={id}
              className={"nav-item " + (tab === id ? "selected" : "")}
              onClick={() => navigate(id)}
              aria-current={tab === id ? "page" : undefined}
            >
              <Icon />
              {t(en, ar)}
            </button>
          ))}
        </nav>
        <Button className="w-full" onClick={() => setCompose(true)}>
          <Feather />
          {t("Share a thought", "شارك فكرة")}
        </Button>
        <div className="rail-bottom stack">
          <button className="nav-item" onClick={() => setCollections(true)}>
            <Bookmark />
            {t("Saved collections", "المحفوظات")}
          </button>
          <button
            className="row"
            style={{ textAlign: "start" }}
            onClick={() => setSettings(true)}
          >
            <Avatar name={user!.name} src={user!.avatar} />
            <div className="grow">
              <strong className="small">{user!.name}</strong>
              <p className="meta">
                <bdi>@{user!.username}</bdi>
              </p>
            </div>
            <Settings className="muted" />
          </button>
        </div>
      </Sidebar>
      <div className="main-grid">
        <main className="workspace">
          <header className="topbar">
            <div>
              <h1>{t(title.en, title.ar)}</h1>
              <small className="muted">
                {tab === "home"
                  ? new Intl.DateTimeFormat(language, {
                      weekday: "long",
                      month: "long",
                      day: "numeric",
                    }).format(new Date())
                  : tab === "discover"
                    ? t("Follow your curiosity", "اتبع فضولك")
                    : tab === "circles"
                      ? t("Something in common", "ما يجمعكم")
                      : tab === "messages"
                        ? t("A little closer", "تواصل أقرب")
                        : t("A space that feels like you", "مساحة تعبّر عنك")}
              </small>
            </div>
            <div className="row" style={{ gap: 4 }}>
              <IconButton
                label={t("Create post", "إنشاء منشور")}
                onClick={() => setCompose(true)}
              >
                <Feather />
              </IconButton>
              <IconButton
                label={t("Notifications", "الإشعارات")}
                onClick={() => setNotifications(true)}
              >
                <Bell />
                {notice.data.items.some((n) => !n.read) && (
                  <span className="dot" />
                )}
              </IconButton>
            </div>
          </header>
          {!online && (
            <div className="offline-banner" role="status">
              {t(
                "You’re offline. Drafts stay on this device until you reconnect.",
                "أنت غير متصل. تبقى مسوداتك على الجهاز حتى عودة الاتصال.",
              )}
            </div>
          )}
          <section
            className="page-scroll"
            hidden={tab !== "home"}
            aria-label={t("Home feed", "منشورات الرئيسية")}
          >
            <Tabs value={mode} onValueChange={setMode} className="feed-tabs">
              <TabsList variant="line">
                <TabsTrigger value="for-you">{t("For you", "لك")}</TabsTrigger>
                <TabsTrigger value="following">
                  {t("Following", "المتابَعون")}
                </TabsTrigger>
              </TabsList>
            </Tabs>
            <Moments onCreate={() => setMoment(true)} />
            <div className="composer-prompt">
              <Avatar name={user!.name} src={user!.avatar} />
              <button onClick={() => setCompose(true)}>
                {t("What’s on your mind, ", "بماذا تفكر يا ") +
                  user!.name.split(" ")[0] +
                  t("?", "؟")}
              </button>
              <IconButton
                label={t("Share music", "مشاركة موسيقى")}
                onClick={() => setCompose(true)}
              >
                <Music2 className="ink" />
              </IconButton>
            </div>
            <div className="feed-label">
              <span>
                {mode === "following"
                  ? t("From people you follow", "من الأشخاص الذين تتابعهم")
                  : t("Thoughts worth a little time", "أفكار تستحق بعض الوقت")}
              </span>
              <Choice
                value={mode === "following" ? "chronological" : sort}
                onChange={setSort}
                label={t("Feed order", "ترتيب المنشورات")}
                options={
                  mode === "following"
                    ? [["chronological", t("Latest first", "الأحدث أولًا")]]
                    : [
                        ["relevant", t("Relevant", "ذات صلة")],
                        ["chronological", t("Latest", "الأحدث")],
                      ]
                }
              />
            </div>
            <FeedList
              path={"feed?mode=" + mode + "&sort=" + sort}
              action={
                <Button variant="outline" onClick={() => navigate("discover")}>
                  {t("Discover your people", "اكتشف أشخاصًا يشبهونك")}
                  <ArrowRight />
                </Button>
              }
            />
          </section>
          <section className="page-scroll" hidden={tab !== "discover"}>
            <Discover
              openCircle={(id) => {
                setCircle(id);
                setTab("circles");
              }}
            />
          </section>
          <section className="page-scroll" hidden={tab !== "circles"}>
            <Circles selected={circle} setSelected={setCircle} />
          </section>
          <section
            className="page-scroll"
            hidden={tab !== "messages"}
            style={
              tab === "messages"
                ? { display: "flex", flexDirection: "column" }
                : undefined
            }
          >
            <Messages
              selected={chat}
              setSelected={setChat}
              active={tab === "messages"}
            />
          </section>
          <section className="page-scroll" hidden={tab !== "space"}>
            <Profile id={user!.id} onSettings={() => setSettings(true)} />
          </section>
        </main>
        <aside className="aside">
          <div className="aside-section">
            <span className="eyebrow">
              {t("Your little corner", "ركنك الخاص")}
            </span>
            <div className="row mt-5">
              <Avatar name={user!.name} src={user!.avatar} />
              <div>
                <strong>{user!.name}</strong>
                <p className="meta">
                  <bdi>@{user!.username}</bdi>
                </p>
              </div>
            </div>
            <p className="small muted mt-4" dir="auto">
              {user!.bio ||
                t(
                  "A thought, a song, a small piece of your day. Make yourself at home.",
                  "فكرة، أغنية، أو شيء من يومك. هذه مساحتك.",
                )}
            </p>
            <div className="row wrap mt-4">
              {user!.interests.slice(0, 4).map((i) => (
                <button
                  key={i}
                  className="pill"
                  onClick={() => navigate("discover")}
                >
                  {interestLabels[i] ? t(...interestLabels[i]) : i}
                </button>
              ))}
            </div>
          </div>
          <div className="aside-section">
            <span className="eyebrow">
              {t("People you might connect with", "أشخاص قد تود معرفتهم")}
            </span>
            {suggested.data.items.length ? (
              suggested.data.items
                .slice(0, 3)
                .map((p) => <PersonRow person={p} key={p.id} />)
            ) : (
              <p className="small muted mt-4">
                {t(
                  "As people join, you’ll find suggestions based on shared interests here.",
                  "مع انضمام أشخاص جدد، ستجد هنا اقتراحات تستند إلى الاهتمامات المشتركة.",
                )}
              </p>
            )}
          </div>
          <div>
            <div className="row between">
              <span className="eyebrow">
                {t("Make room for more", "مساحة لما تحب")}
              </span>
              <Music2 className="ink" />
            </div>
            <p className="small muted mt-4">
              {t(
                "Set a song on your profile. Sometimes a little music says a lot.",
                "اختر أغنية لملفك. أحيانًا تقول الموسيقى الكثير.",
              )}
            </p>
            <button
              className="row small ink mt-4"
              onClick={() => navigate("space")}
            >
              {t("Go to My Space", "انتقل إلى مساحتي")}
              <ArrowUpRight />
            </button>
          </div>
          <div className="meta mt-auto">
            Openly · {t("Thoughtfully connected", "تواصل باهتمام")}
            <p className="mt-2">
              {t(
                "Your saved collections stay private.",
                "مجموعاتك المحفوظة تبقى خاصة.",
              )}{" "}
              <Lock style={{ display: "inline", width: 12, height: 12 }} />
            </p>
          </div>
        </aside>
      </div>
      <nav
        className="bottom-nav"
        aria-label={t("Main navigation", "التنقل الرئيسي")}
      >
        {destinations.map(({ id, en, ar, icon: Icon }) => (
          <button
            key={id}
            className={tab === id ? "selected" : ""}
            onClick={() => navigate(id)}
            aria-current={tab === id ? "page" : undefined}
          >
            <Icon />
            <span>{t(en, ar)}</span>
          </button>
        ))}
      </nav>
      <Composer open={compose} onClose={() => setCompose(false)} />
      <Composer open={moment} onClose={() => setMoment(false)} kind="moment" />
      {notifications && (
        <NotificationCenter
          items={notice.data.items}
          reload={notice.reload}
          onClose={() => setNotifications(false)}
        />
      )}{" "}
      {settings && <SettingsPanel onClose={() => setSettings(false)} />}{" "}
      {collections && <Collections onClose={() => setCollections(false)} />}
    </SidebarProvider>
  );
}
function NotificationCenter({
  items,
  onClose,
  reload,
}: {
  items: Notice[];
  onClose: () => void;
  reload: () => void;
}) {
  const { t, openPost, openProfile, openChat } = useApp();
  const requests = useResource<{ items: User[] }>("requests", { items: [] });
  const { busy, run } = useAction();
  const labels: Record<string, string> = {
    like: t("liked your post", "أعجب بمنشورك"),
    comment: t("replied to a conversation", "ردّ في نقاش"),
    follow: t("connected with you", "تواصل معك"),
    follow_request: t("requested to follow you", "طلب متابعتك"),
    message_request: t("wants to start a conversation", "يريد بدء محادثة"),
    message: t("sent you a message", "أرسل لك رسالة"),
  };
  return (
    <Modal open title={t("Notifications", "الإشعارات")} onClose={onClose}>
      <div className="stack">
        <Button
          variant="ghost"
          disabled={busy}
          onClick={() =>
            run(async () => {
              await api("notifications", "POST");
              reload();
            })
          }
        >
          <Check />
          {t("Mark all as read", "تحديد الكل كمقروء")}
        </Button>
        {requests.data.items.map((u) => (
          <div key={u.id} className="person-row wrap">
            <Avatar name={u.name} src={u.avatar} />
            <strong className="grow">{u.name}</strong>
            <Button
              disabled={busy}
              onClick={() =>
                run(async () => {
                  await api("requests/" + u.id, "POST", { accept: true });
                  requests.reload();
                  reload();
                })
              }
            >
              {t("Accept follow", "قبول المتابعة")}
            </Button>
            <Button
              variant="ghost"
              disabled={busy}
              onClick={() =>
                run(async () => {
                  await api("requests/" + u.id, "POST", { accept: false });
                  requests.reload();
                })
              }
            >
              {t("Decline", "رفض")}
            </Button>
          </div>
        ))}
        {!items.length && (
          <EmptyState
            icon={<Bell />}
            title={t("All quiet for now.", "كل شيء هادئ الآن.")}
            description={t(
              "Replies, reactions, and new connections will appear here.",
              "ستظهر هنا الردود والتفاعلات والعلاقات الجديدة.",
            )}
          />
        )}{" "}
        {items.map((n) => (
          <button
            className={"notice-row " + (!n.read ? "unread" : "")}
            key={n.id}
            style={{ textAlign: "start" }}
            onClick={() =>
              run(async () => {
                await api("notifications/" + n.id, "POST");
                reload();
                onClose();
                if (["like", "comment"].includes(n.type)) openPost(n.target);
                else if (["message", "message_request"].includes(n.type))
                  openChat(n.target);
                else openProfile(n.actor);
              })
            }
          >
            <Avatar name={n.name} src={n.avatar} />
            <span className="grow small">
              <strong>{n.name}</strong> {labels[n.type]}{" "}
              {!n.read && <span className="badge">{t("New", "جديد")}</span>}
            </span>
          </button>
        ))}
      </div>
    </Modal>
  );
}
