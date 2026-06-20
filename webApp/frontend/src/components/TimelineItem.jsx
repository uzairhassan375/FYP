import {
  Award,
  CheckCircle2,
  Clock,
  FileText,
  XCircle,
} from "lucide-react";

const ICON_MAP = {
  CheckCircle: CheckCircle2,
  CheckCircle2: CheckCircle2,
  XCircle,
  Clock,
  Award,
  FileText,
};

function resolveLogIcon(icon) {
  if (!icon || typeof icon !== "string") return FileText;
  const trimmed = icon.trim();
  if (ICON_MAP[trimmed]) return ICON_MAP[trimmed];
  // Emoji or very short non-component labels
  if (trimmed.length <= 2 || !/^[A-Za-z]/.test(trimmed)) return null;
  return FileText;
}

function colorClasses(color) {
  switch (color) {
    case "green":
      return { bg: "bg-green-100", text: "text-green-600" };
    case "red":
      return { bg: "bg-red-100", text: "text-red-600" };
    case "amber":
      return { bg: "bg-amber-100", text: "text-amber-600" };
    case "blue":
      return { bg: "bg-blue-100", text: "text-blue-600" };
    default:
      return { bg: "bg-purple-100", text: "text-purple-600" };
  }
}

export default function TimelineItem({ log }) {
  const IconComponent = resolveLogIcon(log.icon);
  const colors = colorClasses(log.color);

  return (
    <div className="flex items-start gap-4 p-4 border rounded-xl hover:bg-slate-50">
      <div
        className={`w-10 h-10 shrink-0 flex items-center justify-center rounded-full ${colors.bg}`}
      >
        {IconComponent ? (
          <IconComponent className={`w-5 h-5 ${colors.text}`} aria-hidden />
        ) : (
          <span className="text-lg leading-none">{log.icon || "📄"}</span>
        )}
      </div>

      <div className="flex-1 min-w-0">
        <p className="font-semibold">{log.action}</p>
        <p className="text-sm text-slate-500">
          by {log.user} • Related:{" "}
          <span className="font-mono">{log.relatedId}</span>
        </p>
        <p className="text-sm text-slate-400">{log.description}</p>
      </div>

      <p className="text-sm text-slate-400 whitespace-nowrap shrink-0">
        {log.time}
      </p>
    </div>
  );
}
