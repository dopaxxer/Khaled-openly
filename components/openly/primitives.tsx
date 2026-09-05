/* eslint-disable @next/next/no-img-element -- Private media must retain session authorization and no-store access checks; uploaded images are resized before storage. */
"use client";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from "@/components/ui/dialog";
import { Empty } from "@/components/ui/empty";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import type { Song } from "@/shared/types";
import {
  AlertCircle,
  ArrowUpRight,
  CircleDashed,
  Loader2,
  X,
} from "lucide-react";
import type { ReactNode } from "react";
import { errorText, useApp } from "./context";
export { Button };
export function Brand() {
  return (
    <span className="brand">
      <CircleDashed aria-hidden="true" />
      openly
    </span>
  );
}
export function Avatar({
  name,
  src,
  large = false,
}: {
  name: string;
  src?: string | null;
  large?: boolean;
}) {
  return (
    <span className={"avatar" + (large ? " large" : "")} aria-hidden="true">
      {src ? (
        <img src={"/api/media/" + src} alt="" />
      ) : (
        name.slice(0, 1).toUpperCase()
      )}
    </span>
  );
}
export function IconButton({
  label,
  children,
  onClick,
  disabled = false,
  className = "",
}: {
  label: string;
  children: ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  className?: string;
}) {
  return (
    <button
      type="button"
      className={"icon-button " + className}
      title={label}
      aria-label={label}
      onClick={onClick}
      disabled={disabled}
    >
      {children}
    </button>
  );
}
export function Choice({
  value,
  onChange,
  options,
  label,
}: {
  value: string;
  onChange: (v: string) => void;
  options: [string, string][];
  label: string;
}) {
  const { language } = useApp();
  return (
    <Select
      value={value}
      onValueChange={onChange}
      dir={language === "ar" ? "rtl" : "ltr"}
    >
      <SelectTrigger aria-label={label}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {options.map(([v, l]) => (
          <SelectItem key={v} value={v}>
            {l}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
export function Modal({
  title,
  description,
  open,
  onClose,
  children,
  className = "",
}: {
  title: string;
  description?: string;
  open: boolean;
  onClose: () => void;
  children: ReactNode;
  className?: string;
}) {
  const { t } = useApp();
  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        if (!o) onClose();
      }}
    >
      <DialogContent showCloseButton={false} className={className}>
        <div className="dialog-heading">
          <DialogTitle>{title}</DialogTitle>
          <IconButton label={t("Close", "إغلاق")} onClick={onClose}>
            <X />
          </IconButton>
        </div>
        <DialogDescription className={description ? "" : "sr-only"}>
          {description || title}
        </DialogDescription>
        <div className="modal-body">{children}</div>
      </DialogContent>
    </Dialog>
  );
}
export function Panel({
  title,
  open,
  onClose,
  children,
}: {
  title: string;
  open: boolean;
  onClose: () => void;
  children: ReactNode;
}) {
  const { t, language } = useApp();
  return (
    <Sheet
      open={open}
      onOpenChange={(o) => {
        if (!o) onClose();
      }}
    >
      <SheetContent
        side={language === "ar" ? "left" : "right"}
        showCloseButton={false}
        className="w-full sm:max-w-xl gap-0"
      >
        <SheetHeader>
          <div className="row between">
            <SheetTitle>{title}</SheetTitle>
            <IconButton label={t("Close", "إغلاق")} onClick={onClose}>
              <X />
            </IconButton>
          </div>
          <SheetDescription className="sr-only">{title}</SheetDescription>
        </SheetHeader>
        <div className="sheet-body">{children}</div>
      </SheetContent>
    </Sheet>
  );
}
export function Confirm({
  open,
  title,
  description,
  onCancel,
  onConfirm,
}: {
  open: boolean;
  title: string;
  description: string;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const { t } = useApp();
  return (
    <AlertDialog
      open={open}
      onOpenChange={(o) => {
        if (!o) onCancel();
      }}
    >
      <AlertDialogContent>
        <AlertDialogTitle>{title}</AlertDialogTitle>
        <AlertDialogDescription>{description}</AlertDialogDescription>
        <AlertDialogFooter>
          <AlertDialogCancel onClick={onCancel}>
            {t("Cancel", "إلغاء")}
          </AlertDialogCancel>
          <AlertDialogAction onClick={onConfirm}>
            {t("Confirm", "تأكيد")}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
export function Loading() {
  const { t } = useApp();
  return (
    <div
      className="loading-lines"
      role="status"
      aria-label={t("Loading", "جارٍ التحميل")}
    >
      <Skeleton className="h-10 w-2/3" />
      <Skeleton className="h-5 w-full" />
      <Skeleton className="h-5 w-4/5" />
    </div>
  );
}
export function ErrorState({
  error,
  retry,
}: {
  error: unknown;
  retry: () => void;
}) {
  const { t, language } = useApp();
  return (
    <div className="page-content">
      <div className="error-box stack" role="alert">
        <AlertCircle />
        <p>{errorText(error, language)}</p>
        <Button variant="outline" onClick={retry}>
          {t("Try again", "حاول مجددًا")}
        </Button>
      </div>
    </div>
  );
}
export function EmptyState({
  icon,
  title,
  description,
  action,
}: {
  icon?: ReactNode;
  title: string;
  description: string;
  action?: ReactNode;
}) {
  return (
    <Empty className="empty-state border-0 rounded-none">
      <div className="empty-icon">{icon || <CircleDashed />}</div>
      <h2>{title}</h2>
      <p>{description}</p>
      {action}
    </Empty>
  );
}
export function SongCard({ song }: { song: Song }) {
  const { t } = useApp();
  return (
    <div className="music-card">
      <img src={song.artwork} alt="" width={48} height={48} loading="lazy" />
      <div className="grow">
        <strong className="small" dir="auto">
          {song.title}
        </strong>
        <p className="meta" dir="auto">
          {song.artist}
        </p>
        {song.preview ? (
          <audio
            controls
            preload="none"
            src={song.preview}
            aria-label={t("Song preview", "مقتطف الأغنية")}
          />
        ) : (
          <span className="meta">
            {t("Preview unavailable", "المقتطف غير متاح")}
          </span>
        )}
      </div>
      <a
        className="icon-button"
        href={song.url}
        target="_blank"
        rel="noreferrer"
        aria-label={t("Open in Apple Music", "فتح في Apple Music")}
      >
        <ArrowUpRight />
      </a>
    </div>
  );
}
export function BusyButton({
  busy,
  children,
  ...props
}: React.ComponentProps<typeof Button> & { busy: boolean }) {
  return (
    <Button {...props} disabled={busy || props.disabled}>
      {busy ? <Loader2 className="animate-spin" /> : null}
      {children}
    </Button>
  );
}
