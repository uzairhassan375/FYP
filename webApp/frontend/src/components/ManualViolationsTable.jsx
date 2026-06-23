import { useState, useEffect, useCallback, useMemo } from "react";
import { ExternalLink, Loader2, AlertCircle, ClipboardCheck, Filter, Search } from "lucide-react";
import Badge from "./Badge";
import ManualViolationReviewModal from "./ManualViolationReviewModal";
import { apiGet } from "../lib/api";

const STATUS_SECTIONS = [
  { key: "pending", label: "Pending", description: "Awaiting staff review" },
  { key: "approved", label: "Approved", description: "Confirmed or auto-approved reports" },
  { key: "rejected", label: "Rejected", description: "Dismissed reports" },
];

function subjectSummary(v) {
  const parts = [v.subject_student_name, v.subject_sap_id, v.subject_department].filter(Boolean);
  return parts.length ? parts.join(" · ") : "—";
}

function truncate(text, max) {
  if (!text) return "—";
  const s = String(text);
  return s.length <= max ? s : `${s.slice(0, max)}…`;
}

function normStatus(v) {
  return String(v.status || "pending").trim().toLowerCase();
}

function ManualRow({ v, onReview }) {
  return (
    <tr className="border-b hover:bg-slate-50 group">
      <td className="p-3 align-middle text-center sticky left-0 z-10 bg-white group-hover:bg-slate-50 border-r border-slate-100">
        <div className="flex flex-col items-stretch gap-2">
          <button
            type="button"
            onClick={() => onReview(v)}
            className="inline-flex items-center justify-center gap-1 px-2 py-1.5 rounded-lg text-xs font-semibold bg-blue-600 text-white hover:bg-blue-700 border border-blue-700 shadow-sm"
          >
            <ClipboardCheck className="w-3.5 h-3.5 shrink-0" />
            Review
          </button>
          {v.evidenceSignedUrl ? (
            <a
              href={v.evidenceSignedUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center gap-1 px-2 py-1.5 rounded-lg text-xs font-medium bg-blue-50 text-blue-600 hover:bg-blue-100 border border-blue-200"
            >
              <ExternalLink className="w-3.5 h-3.5 shrink-0" />
              Open file
            </a>
          ) : (
            <span className="text-[10px] text-slate-400 leading-tight">No file link</span>
          )}
        </div>
      </td>
      <td className="p-4">
        <Badge text={normStatus(v)} variant={normStatus(v)} />
        {v.ai_status && (
          <div className="text-[10px] text-slate-400 mt-1 capitalize">
            AI: {String(v.ai_status).replace(/_/g, " ")}
          </div>
        )}
      </td>
      <td className="p-4 font-mono text-xs font-medium">{String(v.id).slice(0, 8)}…</td>
      <td className="p-4">
        <div className="font-medium">{v.reporterName || "—"}</div>
        <div className="text-xs text-slate-500">{v.reporterEmail || ""}</div>
      </td>
      <td className="p-4 capitalize">{v.category ?? "—"}</td>
      <td className="p-4 max-w-[220px]" title={v.description}>
        {truncate(v.description, 100)}
      </td>
      <td className="p-4">{v.location ?? "—"}</td>
      <td className="p-4 text-slate-700">{subjectSummary(v)}</td>
      <td className="p-4 capitalize">{v.evidence_media_type ?? "—"}</td>
      <td className="p-4 text-slate-500 whitespace-nowrap">{v.time ?? "—"}</td>
    </tr>
  );
}

function TableHead() {
  return (
    <thead className="bg-slate-50 text-slate-600 border-b">
      <tr>
        <th className="p-3 text-center align-middle w-[132px] min-w-[132px] sticky left-0 z-20 bg-slate-50 border-r border-slate-200 shadow-[4px_0_8px_-4px_rgba(0,0,0,0.08)]">
          Actions
        </th>
        <th className="p-4 text-left">Status</th>
        <th className="p-4 text-left">ID</th>
        <th className="p-4 text-left">Reporter</th>
        <th className="p-4 text-left">Category</th>
        <th className="p-4 text-left">Description</th>
        <th className="p-4 text-left">Location</th>
        <th className="p-4 text-left">Subject</th>
        <th className="p-4 text-left">Media</th>
        <th className="p-4 text-left">Submitted</th>
      </tr>
    </thead>
  );
}

export default function ManualViolationsTable() {
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [reviewRow, setReviewRow] = useState(null);
  const [categoryFilter, setCategoryFilter] = useState("all");
  const [statusFilter, setStatusFilter] = useState("all");
  const [search, setSearch] = useState("");

  const canGiveRewards = (() => {
    try {
      const u = JSON.parse(localStorage.getItem("user") || "{}");
      const r = u.role;
      return r === "admin" || r === "discipline_incharge" || r === "teacher";
    } catch {
      return false;
    }
  })();

  const fetchRows = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const data = await apiGet("/api/manual-violations");
      setRows(Array.isArray(data) ? data : []);
      setError("");
    } catch (err) {
      setError(err.message);
    } finally {
      if (!silent) setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchRows();
    const id = setInterval(() => fetchRows(true), 15000);
    return () => clearInterval(id);
  }, [fetchRows]);

  const categories = useMemo(() => {
    const set = new Set();
    for (const v of rows) {
      const c = String(v.category || "").trim();
      if (c) set.add(c);
    }
    return Array.from(set).sort();
  }, [rows]);

  const filtered = useMemo(() => {
    return rows.filter((v) => {
      const c = String(v.category || "").trim();
      const st = normStatus(v);

      const repName = String(v.reporterName || "").toLowerCase();
      const repEmail = String(v.reporterEmail || "").toLowerCase();
      const subjName = String(v.subject_student_name || "").toLowerCase();
      const subjSap = String(v.subject_sap_id || "").toLowerCase();
      const desc = String(v.description || "").toLowerCase();
      const loc = String(v.location || "").toLowerCase();
      const q = search.toLowerCase().trim();

      const matchCategory = categoryFilter === "all" || c === categoryFilter;
      const matchStatus = statusFilter === "all" || st === statusFilter;
      const matchSearch =
        !q ||
        repName.includes(q) ||
        repEmail.includes(q) ||
        subjName.includes(q) ||
        subjSap.includes(q) ||
        desc.includes(q) ||
        loc.includes(q) ||
        String(v.id).toLowerCase().includes(q);

      return matchCategory && matchStatus && matchSearch;
    });
  }, [rows, categoryFilter, statusFilter, search]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="w-8 h-8 text-blue-600 animate-spin" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-xl p-4 flex items-center gap-3 text-red-600">
        <AlertCircle className="shrink-0" />
        <p>{error}</p>
      </div>
    );
  }

  if (rows.length === 0) {
    return (
      <div className="bg-slate-50 border border-slate-200 rounded-xl p-8 text-center text-slate-600 text-sm">
        No manual violation reports yet. Reports submitted from the student mobile app will appear here.
      </div>
    );
  }

  return (
    <>
      <div className="flex flex-wrap items-center justify-between gap-4 mb-6 bg-white border border-slate-100 rounded-xl p-4 shadow-sm">
        <div className="flex flex-wrap items-center gap-4 flex-1">
          <div className="relative flex-1 min-w-[240px] max-w-[360px]">
            <Search className="absolute left-3 top-2.5 text-slate-400 w-4 h-4" />
            <input
              type="text"
              placeholder="Search reporter, SAP ID, subject..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-4 py-1.5 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/20"
            />
          </div>

          <div className="flex items-center gap-2 text-sm">
            <span className="text-slate-500 font-semibold flex items-center gap-1">
              <Filter className="w-4 h-4" /> Category:
            </span>
            <select
              value={categoryFilter}
              onChange={(e) => setCategoryFilter(e.target.value)}
              className="border border-slate-200 rounded-lg px-3 py-1.5 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/20 capitalize min-w-[150px]"
            >
              <option value="all">All Categories</option>
              {categories.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </div>

          <div className="flex items-center gap-2 text-sm">
            <span className="text-slate-500 font-semibold">Status:</span>
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              className="border border-slate-200 rounded-lg px-3 py-1.5 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/20 min-w-[150px]"
            >
              <option value="all">All Statuses</option>
              {STATUS_SECTIONS.map((s) => (
                <option key={s.key} value={s.key}>
                  {s.label}
                </option>
              ))}
            </select>
          </div>
        </div>

        <span className="text-xs font-semibold text-slate-400">
          Showing {filtered.length} of {rows.length} reports
        </span>
      </div>

      <p className="text-xs text-slate-500 mb-3">
        Use <span className="font-semibold text-slate-700">Review</span> to approve, reject, or add notes.
      </p>

      {filtered.length === 0 ? (
        <div className="bg-slate-50 border border-slate-200 rounded-xl p-8 text-center text-slate-500 text-sm">
          No reports match the selected filters.
        </div>
      ) : (
        <div className="bg-white border rounded-xl overflow-x-auto shadow-sm">
          <table className="w-full text-sm min-w-[920px]">
            <TableHead />
            <tbody>
              {filtered.map((v) => (
                <ManualRow key={v.id} v={v} onReview={setReviewRow} />
              ))}
            </tbody>
          </table>
        </div>
      )}

      {reviewRow && (
        <ManualViolationReviewModal
          row={reviewRow}
          canGiveRewards={canGiveRewards}
          onClose={() => setReviewRow(null)}
          onSaved={() => fetchRows(true)}
        />
      )}
    </>
  );
}
