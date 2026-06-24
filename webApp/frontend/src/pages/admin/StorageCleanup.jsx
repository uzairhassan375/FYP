import { useCallback, useEffect, useState } from "react";
import {
  AlertCircle,
  CheckCircle2,
  HardDrive,
  Loader2,
  RefreshCw,
  Trash2,
} from "lucide-react";
import Topbar from "../../components/Topbar";
import { apiGet, apiPost } from "../../lib/api";

export default function StorageCleanup() {
  const [report, setReport] = useState(null);
  const [loading, setLoading] = useState(true);
  const [deleting, setDeleting] = useState(false);
  const [selected, setSelected] = useState(new Set());
  const [expanded, setExpanded] = useState(new Set());
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const data = await apiGet("/api/admin/storage-cleanup");
      setReport(data);
      setSelected(
        new Set(
          (data.categories || [])
            .filter((c) => c.orphanCount > 0)
            .map((c) => c.id),
        ),
      );
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const toggleCategory = (id) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleExpanded = (id) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const handleDelete = async () => {
    if (!selected.size) {
      setError("Select at least one category to clean up.");
      return;
    }
    const labels = (report?.categories || [])
      .filter((c) => selected.has(c.id))
      .map((c) => c.label)
      .join(", ");
    const ok = window.confirm(
      `Delete unneeded files in:\n\n${labels}\n\nThis cannot be undone. Continue?`,
    );
    if (!ok) return;

    setDeleting(true);
    setError("");
    setSuccess("");
    try {
      const result = await apiPost("/api/admin/storage-cleanup/delete", {
        categories: Array.from(selected),
      });
      setSuccess(
        `Deleted ${result.totalDeleted} item(s), freed ${result.totalFreedLabel}.`,
      );
      await load();
      setTimeout(() => setSuccess(""), 6000);
    } catch (err) {
      setError(err.message);
    } finally {
      setDeleting(false);
    }
  };

  return (
    <>
      <Topbar />

      <div className="p-6 max-w-5xl">
        <div className="flex flex-wrap items-start justify-between gap-4 mb-6">
          <div>
            <h1 className="text-2xl font-bold text-slate-900">Storage Cleanup</h1>
            <p className="text-slate-500 mt-1 max-w-2xl">
              Remove temporary uploads, processed offline videos, and orphaned Supabase
              files that are no longer linked to violations or reports.
            </p>
          </div>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={load}
              disabled={loading || deleting}
              className="inline-flex items-center gap-2 border border-slate-200 bg-white px-4 py-2 rounded-lg text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:opacity-60"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} />
              Rescan
            </button>
            <button
              type="button"
              onClick={handleDelete}
              disabled={loading || deleting || !selected.size}
              className="inline-flex items-center gap-2 bg-red-600 text-white px-4 py-2 rounded-lg text-sm font-semibold hover:bg-red-700 disabled:opacity-60"
            >
              {deleting ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <Trash2 className="w-4 h-4" />
              )}
              Delete selected
            </button>
          </div>
        </div>

        {error && (
          <div className="mb-4 bg-red-50 border border-red-200 rounded-xl p-4 flex items-center gap-3 text-red-600 text-sm">
            <AlertCircle className="shrink-0" size={18} />
            {error}
          </div>
        )}

        {success && (
          <div className="mb-4 bg-emerald-50 border border-emerald-200 rounded-xl p-4 flex items-center gap-3 text-emerald-700 text-sm">
            <CheckCircle2 className="shrink-0" size={18} />
            {success}
          </div>
        )}

        {loading ? (
          <div className="bg-white border rounded-xl p-16 flex justify-center">
            <Loader2 className="w-8 h-8 text-blue-600 animate-spin" />
          </div>
        ) : (
          <>
            {report?.summary && (
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
                <div className="bg-white border rounded-xl p-4">
                  <p className="text-xs font-semibold uppercase tracking-wider text-slate-400">
                    Orphan items
                  </p>
                  <p className="text-2xl font-bold text-slate-900 mt-1">
                    {report.summary.orphanFiles}
                  </p>
                </div>
                <div className="bg-white border rounded-xl p-4">
                  <p className="text-xs font-semibold uppercase tracking-wider text-slate-400">
                    Reclaimable space
                  </p>
                  <p className="text-2xl font-bold text-amber-600 mt-1">
                    {report.summary.orphanSizeLabel}
                  </p>
                </div>
                <div className="bg-white border rounded-xl p-4">
                  <p className="text-xs font-semibold uppercase tracking-wider text-slate-400">
                    Last scanned
                  </p>
                  <p className="text-sm font-medium text-slate-700 mt-2">
                    {report.scannedAt
                      ? new Date(report.scannedAt).toLocaleString()
                      : "—"}
                  </p>
                </div>
              </div>
            )}

            <div className="space-y-4">
              {(report?.categories || []).map((cat) => (
                <div
                  key={cat.id}
                  className="bg-white border rounded-xl shadow-sm overflow-hidden"
                >
                  <div className="px-5 py-4 flex flex-wrap items-start gap-4 border-b bg-slate-50">
                    <label className="flex items-start gap-3 flex-1 min-w-[200px] cursor-pointer">
                      <input
                        type="checkbox"
                        checked={selected.has(cat.id)}
                        disabled={cat.orphanCount === 0}
                        onChange={() => toggleCategory(cat.id)}
                        className="mt-1 rounded border-slate-300"
                      />
                      <div>
                        <div className="flex items-center gap-2">
                          <HardDrive size={16} className="text-slate-500" />
                          <h2 className="font-semibold text-slate-800">{cat.label}</h2>
                          <span
                            className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full ${
                              cat.storage === "supabase"
                                ? "bg-violet-100 text-violet-700"
                                : "bg-slate-200 text-slate-600"
                            }`}
                          >
                            {cat.storage}
                          </span>
                        </div>
                        <p className="text-sm text-slate-500 mt-1">{cat.description}</p>
                        <p className="text-xs text-slate-400 mt-1 font-mono">{cat.location}</p>
                      </div>
                    </label>
                    <div className="text-right shrink-0">
                      <p className="text-lg font-bold text-slate-900">{cat.orphanCount}</p>
                      <p className="text-xs text-slate-500">items · {cat.orphanSizeLabel}</p>
                    </div>
                  </div>

                  {cat.orphanCount > 0 && (
                    <div className="px-5 py-3">
                      <button
                        type="button"
                        onClick={() => toggleExpanded(cat.id)}
                        className="text-xs font-semibold text-blue-600 hover:text-blue-700"
                      >
                        {expanded.has(cat.id) ? "Hide" : "Show"} file list
                        {cat.truncated ? " (first 200)" : ""}
                      </button>
                      {expanded.has(cat.id) && (
                        <div className="mt-3 max-h-56 overflow-y-auto border rounded-lg divide-y">
                          {(cat.files || []).map((file) => (
                            <div
                              key={`${cat.id}-${file.path || file.name}`}
                              className="px-3 py-2 flex justify-between gap-3 text-sm"
                            >
                              <span className="text-slate-700 truncate font-mono text-xs">
                                {file.path || file.name}
                              </span>
                              <span className="text-slate-400 shrink-0 text-xs">
                                {file.sizeLabel}
                              </span>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  )}

                  {cat.orphanCount === 0 && (
                    <div className="px-5 py-3 text-sm text-emerald-600">Nothing to clean up.</div>
                  )}
                </div>
              ))}
            </div>

            <div className="mt-6 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
              <strong>Note:</strong> This only removes unreferenced or temporary files. Active
              violation clips, manual report evidence, and student enrollment videos linked in the
              database are not deleted.
            </div>
          </>
        )}
      </div>
    </>
  );
}
