/* eslint-disable react-hooks/set-state-in-effect -- Effects hydrate external session, network, and device draft state; updates are bounded by resource identity. */
"use client";
import type { User } from "@/shared/types";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
} from "react";
import { toast } from "sonner";
export type Language = "en" | "ar";
export const AppContext = createContext<{
  user: User | null;
  setUser: (u: User | null) => void;
  language: Language;
  setLanguage: (l: Language) => void;
  t: (en: string, ar: string) => string;
  refresh: number;
  bump: () => void;
  openProfile: (id: string) => void;
  openPost: (id: string) => void;
  openChat: (id: string) => void;
}>({
  user: null,
  setUser: () => {},
  language: "en",
  setLanguage: () => {},
  t: (en) => en,
  refresh: 0,
  bump: () => {},
  openProfile: () => {},
  openPost: () => {},
  openChat: () => {},
});
export const useApp = () => useContext(AppContext);
export class RequestError extends Error {
  constructor(
    public code: string,
    public status: number,
  ) {
    super(code);
  }
}
export async function api<T = Record<string, unknown>>(
  path: string,
  method = "GET",
  body?: unknown,
): Promise<T> {
  let response: Response;
  try {
    response = await fetch("/api/" + path, {
      method,
      credentials: "same-origin",
      headers: body ? { "content-type": "application/json" } : {},
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch {
    throw new RequestError("offline", 0);
  }
  let data;
  try {
    data = await response.json();
  } catch {
    throw new RequestError("server_error", response.status);
  }
  if (!response.ok)
    throw new RequestError(data.error || "server_error", response.status);
  return data as T;
}
export const errors: Record<string, [string, string]> = {
  offline: [
    "You’re offline. Your draft is safe. Try again when connected.",
    "أنت غير متصل. مسودتك محفوظة، حاول عند عودة الاتصال.",
  ],
  sign_in: ["Please sign in to continue.", "سجّل الدخول للمتابعة."],
  invalid_credentials: [
    "The email or password is incorrect.",
    "البريد الإلكتروني أو كلمة المرور غير صحيحة.",
  ],
  validation: [
    "Check the highlighted fields and try again.",
    "تحقق من الحقول ثم حاول مجددًا.",
  ],
  account_exists: [
    "This email or username is already in use.",
    "البريد الإلكتروني أو اسم المستخدم مستخدم بالفعل.",
  ],
  invalid_recovery: [
    "The email or recovery code is incorrect.",
    "البريد الإلكتروني أو رمز الاسترداد غير صحيح.",
  ],
  unavailable: [
    "This content is unavailable or no longer shared with you.",
    "هذا المحتوى غير متاح أو لم يعد مشاركًا معك.",
  ],
  forbidden: [
    "You don’t have permission for this action.",
    "ليس لديك إذن لتنفيذ هذا الإجراء.",
  ],
  request_pending: [
    "Wait until your message request is accepted. You can send one text introduction.",
    "انتظر قبول طلب المحادثة. يمكنك إرسال رسالة تعريفية واحدة.",
  ],
  messages_closed: [
    "This person isn’t accepting messages from you.",
    "هذا الشخص لا يستقبل رسائل منك حاليًا.",
  ],
  rate_limited: [
    "A little too fast. Please try again in a minute.",
    "تم تنفيذ إجراءات كثيرة. حاول بعد دقيقة.",
  ],
  too_large: [
    "Choose a file smaller than 10 MB.",
    "اختر ملفًا أصغر من 10 ميغابايت.",
  ],
  unsupported_media: [
    "Use a JPG, PNG, WebP image or a supported audio file.",
    "استخدم صورة JPG أو PNG أو WebP أو ملفًا صوتيًا مدعومًا.",
  ],
  invalid_media: [
    "This file could not be read. Please choose another.",
    "تعذّر قراءة الملف، اختر ملفًا آخر.",
  ],
  upload_quota: [
    "Today’s upload limit has been reached.",
    "وصلت إلى حد الرفع اليومي.",
  ],
  empty_post: [
    "Add a thought, image, or song first.",
    "أضف نصًا أو صورة أو أغنية أولًا.",
  ],
  empty_message: ["Write a message or add a file.", "اكتب رسالة أو أضف ملفًا."],
  music_unavailable: [
    "Music search is unavailable right now. Please try again later.",
    "البحث عن الموسيقى غير متاح حاليًا. حاول لاحقًا.",
  ],
  owner_cannot_leave: [
    "As the owner, delete the Circle from its settings to leave.",
    "بصفتك المالك، احذف الدائرة من إعداداتها للمغادرة.",
  ],
  leave_owned_circles: [
    "Delete your owned Circles before deleting your account.",
    "احذف الدوائر التي تملكها قبل حذف حسابك.",
  ],
  server_error: [
    "Something went wrong. Your draft is safe. Please try again.",
    "حدث خطأ. مسودتك محفوظة، حاول مجددًا.",
  ],
};
export function errorText(error: unknown, language: Language) {
  const key = error instanceof RequestError ? error.code : "server_error";
  return (errors[key] || errors.server_error)[language === "ar" ? 1 : 0];
}
export function useAction() {
  const { language } = useApp();
  const [busy, setBusy] = useState(false);
  return {
    busy,
    run: async <T,>(fn: () => Promise<T>): Promise<T | undefined> => {
      if (busy) return;
      setBusy(true);
      try {
        return await fn();
      } catch (e) {
        toast.error(errorText(e, language));
        return undefined;
      } finally {
        setBusy(false);
      }
    },
  };
}
export function useResource<T>(path: string | null, initial: T) {
  const { refresh } = useApp();
  const [data, setData] = useState<T>(initial),
    [loading, setLoading] = useState(!!path),
    [error, setError] = useState<unknown>(null);
  const [version, setVersion] = useState(0);
  const reload = useCallback(() => setVersion((v) => v + 1), []);
  useEffect(() => {
    if (!path) return;
    let active = true;
    setLoading(true);
    api<T>(path)
      .then((d) => {
        if (active) {
          setData(d);
          setError(null);
        }
      })
      .catch((e) => {
        if (active) setError(e);
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [path, refresh, version]);
  return { data, setData, loading, error, reload };
}
export const interestLabels: Record<string, [string, string]> = {
  music: ["Music", "الموسيقى"],
  art: ["Art", "الفن"],
  books: ["Books", "الكتب"],
  photography: ["Photography", "التصوير"],
  film: ["Film", "الأفلام"],
  everyday: ["Everyday life", "الحياة اليومية"],
  design: ["Design", "التصميم"],
  science: ["Science", "العلوم"],
  gaming: ["Gaming", "الألعاب"],
  travel: ["Travel", "السفر"],
};
export async function upload(file: Blob) {
  if (file.size > 10 * 1024 * 1024) throw new RequestError("too_large", 413);
  const response = await fetch("/api/media", {
    method: "POST",
    body: file,
    headers: { "content-type": file.type },
  });
  const result = await response.json();
  if (!response.ok) throw new RequestError(result.error, response.status);
  return result as { id: string; type: string; size: number };
}
export async function imageUpload(file: File) {
  if (!file.type.startsWith("image/"))
    throw new RequestError("unsupported_media", 415);
  const bitmap = await createImageBitmap(file);
  const ratio = Math.min(1, 1800 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * ratio);
  canvas.height = Math.round(bitmap.height * ratio);
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  const blob = await new Promise<Blob>((resolve, reject) =>
    canvas.toBlob(
      (b) => (b ? resolve(b) : reject(new Error("image"))),
      "image/jpeg",
      0.85,
    ),
  );
  return upload(blob);
}
export function dateLabel(value: number, language: Language) {
  return new Intl.DateTimeFormat(language === "ar" ? "ar" : "en", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(value);
}
export function countLabel(
  count: number,
  kind: "followers" | "members",
  language: Language,
) {
  const number = new Intl.NumberFormat(language).format(count);
  if (language === "en")
    return `${number} ${kind === "followers" ? (count === 1 ? "follower" : "followers") : count === 1 ? "member" : "members"}`;
  const form = new Intl.PluralRules("ar").select(count);
  const words =
    kind === "followers"
      ? {
          zero: "لا متابعين",
          one: "متابع واحد",
          two: "متابعان",
          few: "متابعين",
          many: "متابعًا",
          other: "متابع",
        }
      : {
          zero: "لا أعضاء",
          one: "عضو واحد",
          two: "عضوان",
          few: "أعضاء",
          many: "عضوًا",
          other: "عضو",
        };
  return ["zero", "one", "two"].includes(form)
    ? words[form]
    : `${number} ${words[form]}`;
}
