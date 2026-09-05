"use client";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import type { Circle } from "@/shared/types";
import {
  ArrowLeft,
  BookOpen,
  Camera,
  Lock,
  Music2,
  Palette,
  Plus,
  Users,
} from "lucide-react";
import { useState } from "react";
import {
  countLabel,
  api,
  interestLabels,
  useAction,
  useApp,
  useResource,
} from "./context";
import { Composer, FeedList } from "./Posts";
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
} from "./primitives";
const icons: Record<string, typeof Music2> = {
  music: Music2,
  art: Palette,
  books: BookOpen,
  photography: Camera,
};
export function CircleRow({
  circle: c,
  onOpen,
}: {
  circle: Circle;
  onOpen: () => void;
}) {
  const { t, bump, user } = useApp();
  const { busy, run } = useAction();
  const Icon = icons[c.interest] || Users;
  return (
    <div className="circle-row">
      <button
        className="row grow"
        onClick={onOpen}
        style={{ textAlign: "start" }}
      >
        <span className="circle-icon">
          <Icon />
        </span>
        <div className="grow">
          <strong className="small">
            {c.name}{" "}
            {c.private === 1 && (
              <Lock style={{ display: "inline", width: 13, height: 13 }} />
            )}
          </strong>
          <p className="meta">
            {countLabel(c.members || 0, "members", user?.language || "en")} ·{" "}
            {interestLabels[c.interest]
              ? t(...interestLabels[c.interest])
              : c.interest}
          </p>
          <p className="small muted" style={{ marginTop: 5 }} dir="auto">
            {c.description.slice(0, 100)}
          </p>
        </div>
      </button>
      {c.status === "accepted" ? (
        <Button variant="ghost" onClick={onOpen}>
          {t("Open", "فتح")}
        </Button>
      ) : (
        <BusyButton
          busy={busy}
          variant="outline"
          disabled={c.status === "pending"}
          onClick={() =>
            run(async () => {
              await api("circles/" + c.id + "/join", "POST");
              bump();
            })
          }
        >
          {c.status === "pending"
            ? t("Requested", "تم الطلب")
            : t("Join", "انضمام")}
        </BusyButton>
      )}
    </div>
  );
}
export function Circles({
  selected,
  setSelected,
}: {
  selected: string | null;
  setSelected: (id: string | null) => void;
}) {
  const { t } = useApp();
  const [create, setCreate] = useState(false);
  const r = useResource<{ items: Circle[] }>("circles", { items: [] });
  return (
    <>
      {selected ? (
        <CircleDetail id={selected} onBack={() => setSelected(null)} />
      ) : (
        <div className="page-content">
          <div className="row between">
            <div>
              <span className="eyebrow">
                {t("Find your corner", "اعثر على دائرتك")}
              </span>
              <h2 style={{ marginTop: 8 }}>
                {t(
                  "Small circles. Shared interests.",
                  "دوائر صغيرة. اهتمامات مشتركة.",
                )}
              </h2>
            </div>
            <IconButton
              label={t("Create Circle", "إنشاء دائرة")}
              onClick={() => setCreate(true)}
            >
              <Plus />
            </IconButton>
          </div>
          {r.loading ? (
            <Loading />
          ) : r.error ? (
            <ErrorState error={r.error} retry={r.reload} />
          ) : r.data.items.length ? (
            r.data.items.map((c) => (
              <CircleRow
                circle={c}
                key={c.id}
                onOpen={() => setSelected(c.id)}
              />
            ))
          ) : (
            <EmptyState
              icon={<Users />}
              title={t("Give an interest a home.", "امنح اهتمامًا مساحة.")}
              description={t(
                "Create the first Circle for music, art, books, or whatever brings you together.",
                "أنشئ أول دائرة للموسيقى أو الفن أو الكتب أو أي اهتمام يجمعكم.",
              )}
              action={
                <Button onClick={() => setCreate(true)}>
                  <Plus />
                  {t("Create a Circle", "إنشاء دائرة")}
                </Button>
              }
            />
          )}
        </div>
      )}
      {create && (
        <CreateCircle
          onClose={() => setCreate(false)}
          onCreated={(id) => {
            setCreate(false);
            setSelected(id);
            r.reload();
          }}
        />
      )}
    </>
  );
}
function CreateCircle({
  onClose,
  onCreated,
}: {
  onClose: () => void;
  onCreated: (id: string) => void;
}) {
  const { t } = useApp();
  const { busy, run } = useAction();
  const [interest, setInterest] = useState("music"),
    [privateCircle, setPrivate] = useState(false);
  return (
    <Modal open title={t("Create a Circle", "إنشاء دائرة")} onClose={onClose}>
      <form
        className="form-grid"
        onSubmit={(e) => {
          e.preventDefault();
          const values = Object.fromEntries(new FormData(e.currentTarget));
          void run(async () => {
            const d = await api<{ id: string }>("circles", "POST", {
              ...values,
              interest,
              private: privateCircle ? 1 : 0,
            });
            onCreated(d.id);
          });
        }}
      >
        <label>
          {t("Circle name", "اسم الدائرة")}
          <Input name="name" minLength={3} maxLength={60} required />
        </label>
        <label>
          {t("What brings you together?", "ما الذي يجمعكم؟")}
          <Textarea name="description" maxLength={500} />
        </label>
        <label>
          {t("Circle rules", "قواعد الدائرة")}
          <Textarea
            name="rules"
            maxLength={1500}
            defaultValue={t(
              "Be kind. Respect each other’s privacy. Stay curious.",
              "كن لطيفًا. احترم خصوصية الآخرين. شارك باهتمام.",
            )}
          />
        </label>
        <Choice
          value={interest}
          onChange={setInterest}
          label={t("Shared interest", "الاهتمام المشترك")}
          options={Object.entries(interestLabels).map(([k, n]) => [k, t(...n)])}
        />
        <div className="settings-row">
          <span>{t("Private Circle", "دائرة خاصة")}</span>
          <Switch
            checked={privateCircle}
            onCheckedChange={setPrivate}
            aria-label={t("Private Circle", "دائرة خاصة")}
          />
        </div>
        <BusyButton type="submit" busy={busy}>
          {t("Create Circle", "إنشاء الدائرة")}
        </BusyButton>
      </form>
    </Modal>
  );
}
function CircleDetail({ id, onBack }: { id: string; onBack: () => void }) {
  const { t, user } = useApp();
  const [tab, setTab] = useState("post"),
    [compose, setCompose] = useState(false),
    [manage, setManage] = useState(false),
    [leave, setLeave] = useState(false);
  const r = useResource<{ circle: Circle }>(
    "circles/" + id,
    {} as { circle: Circle },
  );
  const { busy, run } = useAction();
  if (r.loading) return <Loading />;
  if (r.error)
    return (
      <>
        <Button variant="ghost" onClick={onBack}>
          <ArrowLeft />
          {t("Back to Circles", "العودة إلى الدوائر")}
        </Button>
        <ErrorState error={r.error} retry={r.reload} />
      </>
    );
  const c = r.data.circle;
  return (
    <>
      <div className="page-content stack">
        <div className="row between">
          <IconButton label={t("Back", "رجوع")} onClick={onBack}>
            <ArrowLeft />
          </IconButton>
          <div className="row">
            {c.status === "accepted" && (
              <Button variant="ghost" onClick={() => setManage(true)}>
                <Users />
                {t("Members", "الأعضاء")}
              </Button>
            )}
            {c.status === "accepted" && (
              <Button variant="outline" onClick={() => setLeave(true)}>
                {c.owner === user!.id
                  ? t("Delete Circle", "حذف الدائرة")
                  : t("Leave", "مغادرة")}
              </Button>
            )}
          </div>
        </div>
        <h1>{c.name}</h1>
        <p className="muted" dir="auto">
          {c.description}
        </p>
        <details>
          <summary className="small ink">
            {t("Circle rules", "قواعد الدائرة")}
          </summary>
          <p
            className="small"
            style={{ whiteSpace: "pre-wrap", paddingTop: 12 }}
            dir="auto"
          >
            {c.rules}
          </p>
        </details>
        {c.status === "accepted" ? (
          <Button onClick={() => setCompose(true)}>
            <Plus />
            {tab === "question"
              ? t("Ask a question", "اطرح سؤالًا")
              : tab === "conversation"
                ? t("Start a conversation", "ابدأ نقاشًا")
                : t("Share with your Circle", "شارك مع دائرتك")}
          </Button>
        ) : (
          <BusyButton
            busy={busy}
            onClick={() =>
              run(async () => {
                await api("circles/" + id + "/join", "POST");
                r.reload();
              })
            }
          >
            {t("Join Circle", "انضم إلى الدائرة")}
          </BusyButton>
        )}
      </div>
      <Tabs value={tab} onValueChange={setTab} className="feed-tabs">
        <TabsList variant="line">
          <TabsTrigger value="post">{t("Posts", "منشورات")}</TabsTrigger>
          <TabsTrigger value="conversation">
            {t("Conversation", "نقاش")}
          </TabsTrigger>
          <TabsTrigger value="question">{t("Questions", "أسئلة")}</TabsTrigger>
        </TabsList>
      </Tabs>
      <FeedList path={"feed?circle=" + id + "&kind=" + tab} />
      <Composer
        open={compose}
        onClose={() => setCompose(false)}
        circleId={id}
        kind={tab}
      />
      {manage && <ManageCircle circle={c} onClose={() => setManage(false)} />}
      <Confirm
        open={leave}
        title={
          c.owner === user!.id
            ? t("Delete this Circle?", "حذف هذه الدائرة؟")
            : t("Leave this Circle?", "مغادرة هذه الدائرة؟")
        }
        description={
          c.owner === user!.id
            ? t(
                "All Circle posts and memberships will be deleted.",
                "سيتم حذف جميع منشورات الدائرة وعضوياتها.",
              )
            : t(
                "You can request to join again later.",
                "يمكنك طلب الانضمام مجددًا لاحقًا.",
              )
        }
        onCancel={() => setLeave(false)}
        onConfirm={() =>
          run(async () => {
            await api(
              "circles/" + id + (c.owner === user!.id ? "" : "/leave"),
              c.owner === user!.id ? "DELETE" : "POST",
            );
            setLeave(false);
            onBack();
          })
        }
      />
    </>
  );
}
function ManageCircle({
  circle,
  onClose,
}: {
  circle: Circle;
  onClose: () => void;
}) {
  const { t, user, openProfile } = useApp();
  const mod = ["moderator", "owner"].includes(circle.role || "");
  const r = useResource<{
    items: {
      userId: string;
      name: string;
      username: string;
      avatar: string | null;
      status: string;
      role: string;
    }[];
  }>("circles/" + circle.id + "/members", { items: [] });
  const reports = useResource<{
    items: { id: string; kind: string; target: string; reason: string }[];
  }>(mod ? "reports?circle=" + circle.id : null, { items: [] });
  const { busy, run } = useAction();
  async function operate(userId: string, operation: string) {
    await run(async () => {
      await api("circles/" + circle.id + "/members", "PATCH", {
        userId,
        operation,
      });
      r.reload();
    });
  }
  return (
    <Modal open title={t("Circle members", "أعضاء الدائرة")} onClose={onClose}>
      <div className="stack">
        {r.loading ? (
          <Loading />
        ) : r.error ? (
          <ErrorState error={r.error} retry={r.reload} />
        ) : (
          r.data.items.map((u) => (
            <div className="person-row wrap" key={u.userId}>
              <button
                className="row grow"
                onClick={() => openProfile(u.userId)}
              >
                <Avatar name={u.name} src={u.avatar} />
                <div>
                  <strong>{u.name}</strong>
                  <p className="meta">
                    {u.status === "pending"
                      ? t("Membership request", "طلب عضوية")
                      : u.role === "owner"
                        ? t("Owner", "المالك")
                        : u.role === "moderator"
                          ? t("Moderator", "مشرف")
                          : t("Member", "عضو")}
                  </p>
                </div>
              </button>
              {mod && u.userId !== circle.owner && (
                <div className="row wrap">
                  {u.status === "pending" && (
                    <Button
                      variant="outline"
                      disabled={busy}
                      onClick={() => operate(u.userId, "accept")}
                    >
                      {t("Accept", "قبول")}
                    </Button>
                  )}
                  {circle.owner === user!.id && u.status === "accepted" && (
                    <Button
                      variant="outline"
                      disabled={busy}
                      onClick={() =>
                        operate(
                          u.userId,
                          u.role === "moderator" ? "member" : "moderator",
                        )
                      }
                    >
                      {u.role === "moderator"
                        ? t("Remove moderator", "إلغاء الإشراف")
                        : t("Make moderator", "تعيين مشرف")}
                    </Button>
                  )}
                  <Button
                    variant="ghost"
                    disabled={busy}
                    onClick={() => operate(u.userId, "remove")}
                  >
                    {t("Remove", "إزالة")}
                  </Button>
                </div>
              )}
            </div>
          ))
        )}
        {mod && (
          <>
            <h3>{t("Reports to review", "بلاغات للمراجعة")}</h3>
            {reports.data.items.length ? (
              reports.data.items.map((report) => (
                <div className="stack" key={report.id}>
                  <p dir="auto">{report.reason}</p>
                  <div className="row">
                    <Button
                      variant="outline"
                      disabled={busy}
                      onClick={() =>
                        run(async () => {
                          await api(
                            "reports/" + report.id + "?circle=" + circle.id,
                            "PATCH",
                            { remove: true },
                          );
                          reports.reload();
                        })
                      }
                    >
                      {t(
                        "Remove reported content",
                        "إزالة المحتوى المبلّغ عنه",
                      )}
                    </Button>
                    <Button
                      variant="ghost"
                      disabled={busy}
                      onClick={() =>
                        run(async () => {
                          await api(
                            "reports/" + report.id + "?circle=" + circle.id,
                            "PATCH",
                            { remove: false },
                          );
                          reports.reload();
                        })
                      }
                    >
                      {t("Dismiss report", "إغلاق البلاغ")}
                    </Button>
                  </div>
                </div>
              ))
            ) : (
              <p className="muted small">
                {t("No open reports.", "لا توجد بلاغات مفتوحة.")}
              </p>
            )}
          </>
        )}
      </div>
    </Modal>
  );
}
