"use client";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import type { User } from "@/shared/types";
import { ArrowRight, Check, KeyRound } from "lucide-react";
import { useState } from "react";
import { api, errorText, imageUpload, interestLabels, useApp } from "./context";
import { Brand, BusyButton, Button } from "./primitives";
export function Auth() {
  const { t, setUser, language, setLanguage } = useApp();
  const [mode, setMode] = useState<"login" | "register" | "recover">(
      "register",
    ),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [recovery, setRecovery] = useState(""),
    [pendingUser, setPendingUser] = useState<User | null>(null);
  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError("");
    try {
      const values = Object.fromEntries(new FormData(e.currentTarget));
      const data = await api<{ user: User; recovery?: string }>(
        "auth/" + mode,
        "POST",
        values,
      );
      if (data.recovery) {
        setRecovery(data.recovery);
        setPendingUser(data.user || null);
      } else setUser(data.user);
    } catch (e) {
      setError(errorText(e, language));
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="auth-layout">
      <section className="auth-intro">
        <Brand />
        <div>
          <span className="eyebrow" style={{ color: "#c8d4f3" }}>
            {t("A little more you", "مساحة تشبهك")}
          </span>
          <h1>
            {t(
              "Thoughts.\nMusic.\nYour kind of people.",
              "أفكارك.\nموسيقاك.\nأشخاص يشبهونك.",
            )
              .split("\n")
              .map((s) => (
                <span key={s}>
                  {s}
                  <br />
                </span>
              ))}
          </h1>
          <p>
            {t(
              "A quiet space to share what moves you, and find people who feel it too.",
              "مساحة هادئة تشارك فيها ما يلامسك وتجد من يشاركك الشعور.",
            )}
          </p>
        </div>
        <span className="small" style={{ color: "#c8d4f3" }}>
          {t("Make room for connection.", "امنح التواصل مساحة.")}
        </span>
      </section>
      <section className="auth-main">
        <div className="auth-form">
          <div className="auth-mobile-brand">
            <Brand />
          </div>
          {recovery ? (
            <div className="stack">
              <KeyRound className="ink" />
              <h1>{t("Save your recovery code", "احفظ رمز استرداد حسابك")}</h1>
              <p className="muted small">
                {t(
                  "Keep this somewhere private. You’ll need it to reset your password if you forget it. We won’t show it again.",
                  "احفظه في مكان خاص. ستحتاج إليه لتغيير كلمة المرور إذا نسيتها، ولن نعرضه مرة أخرى.",
                )}
              </p>
              <code className="safe-copy" dir="ltr">
                {recovery}
              </code>
              <Button
                variant="outline"
                onClick={() => {
                  const blob = new Blob(["Openly recovery code\n" + recovery], {
                    type: "text/plain",
                  });
                  const a = document.createElement("a");
                  a.href = URL.createObjectURL(blob);
                  a.download = "openly-recovery.txt";
                  a.click();
                  URL.revokeObjectURL(a.href);
                }}
              >
                {t("Download recovery code", "تنزيل رمز الاسترداد")}
              </Button>
              <Button
                onClick={() => {
                  setRecovery("");
                  if (pendingUser) setUser(pendingUser);
                  else setMode("login");
                }}
              >
                {t("I’ve saved it", "حفظت الرمز")}
                <Check />
              </Button>
            </div>
          ) : (
            <>
              <h1>
                {mode === "register"
                  ? t("Find your people.", "اعثر على أشخاص يشبهونك.")
                  : mode === "recover"
                    ? t("Recover your account", "استرداد حسابك")
                    : t("Welcome back.", "أهلًا بعودتك.")}
              </h1>
              <p className="muted small">
                {mode === "register"
                  ? t(
                      "Create a space that feels like you.",
                      "أنشئ مساحة تعبّر عنك.",
                    )
                  : mode === "recover"
                    ? t(
                        "Use the private code saved when you joined.",
                        "استخدم الرمز الخاص الذي حفظته عند التسجيل.",
                      )
                    : t(
                        "Your conversations are waiting.",
                        "عُد إلى مساحتك ومحادثاتك.",
                      )}
              </p>
              <form onSubmit={submit} className="form-grid">
                {mode === "register" && (
                  <>
                    <label>
                      {t("Display name", "الاسم")}
                      <Input
                        name="name"
                        required
                        maxLength={60}
                        autoComplete="name"
                      />
                    </label>
                    <label>
                      {t("Username", "اسم المستخدم")}
                      <Input
                        name="username"
                        dir="ltr"
                        required
                        minLength={3}
                        maxLength={24}
                        pattern="[a-zA-Z0-9_]{3,24}"
                        autoComplete="username"
                      />
                      <span className="field-help">
                        {t(
                          "3–24 letters, numbers, or underscores.",
                          "من 3 إلى 24 حرفًا لاتينيًا أو رقمًا أو شرطة سفلية.",
                        )}
                      </span>
                    </label>
                  </>
                )}
                <label>
                  {t("Email", "البريد الإلكتروني")}
                  <Input
                    name="email"
                    type="email"
                    dir="ltr"
                    required
                    autoComplete="email"
                  />
                </label>
                {mode === "recover" && (
                  <label>
                    {t("Recovery code", "رمز الاسترداد")}
                    <Input
                      name="recovery"
                      required
                      dir="ltr"
                      autoComplete="off"
                    />
                  </label>
                )}
                <label>
                  {mode === "recover"
                    ? t("New password", "كلمة مرور جديدة")
                    : t("Password", "كلمة المرور")}
                  <Input
                    name="password"
                    type="password"
                    dir="ltr"
                    required
                    minLength={mode === "login" ? 1 : 12}
                    maxLength={256}
                    autoComplete={
                      mode === "login" ? "current-password" : "new-password"
                    }
                  />
                  {mode !== "login" && (
                    <span className="field-help">
                      {t("At least 12 characters.", "12 حرفًا على الأقل.")}
                    </span>
                  )}
                </label>
                {error && (
                  <p className="error small" role="alert">
                    {error}
                  </p>
                )}
                <BusyButton busy={busy} type="submit">
                  {mode === "register"
                    ? t("Create account", "إنشاء حساب")
                    : mode === "recover"
                      ? t("Reset password", "إعادة تعيين كلمة المرور")
                      : t("Sign in", "تسجيل الدخول")}
                  <ArrowRight />
                </BusyButton>
              </form>
              <div className="auth-links">
                <button
                  onClick={() => {
                    setMode(mode === "register" ? "login" : "register");
                    setError("");
                  }}
                >
                  {mode === "register"
                    ? t("Already a member? Sign in", "لديك حساب؟ سجّل الدخول")
                    : t("Create an account", "إنشاء حساب")}
                </button>
                {mode === "login" && (
                  <button onClick={() => setMode("recover")}>
                    {t("Forgot password?", "نسيت كلمة المرور؟")}
                  </button>
                )}
              </div>
            </>
          )}
          <div className="divider" />
          <button
            className="small ink"
            onClick={() => setLanguage(language === "ar" ? "en" : "ar")}
          >
            {language === "ar" ? "English" : "العربية"}
          </button>
        </div>
      </section>
    </div>
  );
}
export function Onboarding() {
  const { user, setUser, t, language } = useApp();
  const [chosen, setChosen] = useState<string[]>(user?.interests || []),
    [bio, setBio] = useState(""),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [avatar, setAvatar] = useState<string | null>(null);
  async function finish(skip = false) {
    setBusy(true);
    try {
      const data = await api<{ user: User }>("me", "PATCH", {
        interests: skip ? [] : chosen,
        bio: skip ? "" : bio,
        avatar,
        onboarded: 1,
        language,
      });
      setUser(data.user);
    } catch (e) {
      setError(errorText(e, language));
    } finally {
      setBusy(false);
    }
  }
  return (
    <main className="onboard stack">
      <Brand />
      <span className="eyebrow">
        {t("Make yourself at home", "مساحتك تبدأ هنا")}
      </span>
      <h1>{t("What draws you in?", "ما الذي يثير اهتمامك؟")}</h1>
      <p className="muted">
        {t(
          "Choose a few interests. They help you discover people and Circles with something in common.",
          "اختر بعض اهتماماتك لتكتشف أشخاصًا ودوائر تجمعك بهم أشياء مشتركة.",
        )}
      </p>
      <div className="row wrap">
        {Object.entries(interestLabels).map(([key, names]) => (
          <button
            key={key}
            className={"pill " + (chosen.includes(key) ? "selected" : "")}
            aria-pressed={chosen.includes(key)}
            onClick={() =>
              setChosen((s) =>
                s.includes(key) ? s.filter((x) => x !== key) : [...s, key],
              )
            }
          >
            {t(...names)}
          </button>
        ))}
      </div>
      <label className="small stack">
        {t("A little about you (optional)", "نبذة عنك (اختياري)")}
        <Textarea
          value={bio}
          onChange={(e) => setBio(e.target.value)}
          maxLength={300}
        />
      </label>
      <label className="small stack">
        {t("Profile photo (optional)", "صورة شخصية (اختياري)")}
        <Input
          type="file"
          accept="image/*"
          onChange={async (e) => {
            if (e.target.files?.[0])
              try {
                setAvatar((await imageUpload(e.target.files[0])).id);
              } catch (e) {
                setError(errorText(e, language));
              }
          }}
        />
        {avatar && (
          <span className="ink">{t("Photo ready", "الصورة جاهزة")}</span>
        )}
      </label>
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      <BusyButton busy={busy} onClick={() => finish()}>
        {t("Enter your space", "ادخل مساحتك")}
        <ArrowRight />
      </BusyButton>
      <Button variant="ghost" disabled={busy} onClick={() => finish(true)}>
        {t("Skip for now", "تخطّ الآن")}
      </Button>
    </main>
  );
}
