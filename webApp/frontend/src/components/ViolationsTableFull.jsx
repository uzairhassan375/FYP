import { useState, useEffect, useCallback, useMemo } from "react";
import { Eye, Loader2, AlertCircle, Video, Filter, ClipboardCheck, Search } from "lucide-react";
import Badge from "./Badge";
import VideoClipModal from "./VideoClipModal";
import ApproveViolationModal from "./ApproveViolationModal";
import { apiGet } from "../lib/api";

const STATUS_SECTIONS = [
  { key: "PendingReview", label: "Pending review", description: "Awaiting incharge review" },
  { key: "Unverified", label: "Unverified", description: "Detected but not yet verified" },
  { key: "Verified", label: "Verified", description: "Confirmed violations" },
  { key: "Dismissed", label: "Dismissed", description: "Rejected or cleared" },
];

function normStatus(v) {
  return String(v.status || "Unverified").trim();
}

function ViolationRow({ v, onSelect, canReview, onReview }) {
  const status = normStatus(v);
  const isReviewable = true; // All camera violations are reviewable to allow corrections and re-assignments

  return (
    <tr className="border-b hover:bg-slate-50">
      <td className="p-4 font-medium font-mono text-xs">
        {v.studentRollNumber || `${String(v._id || v.id).slice(0, 8)}…`}
      </td>
      <td className="p-4">
        <div className="font-medium">{v.student ?? v.studentName ?? "Unknown"}</div>
      </td>
      <td className="p-4 capitalize">{v.type ?? "-"}</td>
      <td className="p-4">
        <Badge text={v.severity ?? "—"} variant={v.severity} />
      </td>
      <td className="p-4">{v.confidence ?? "-"}</td>
      <td className="p-4">{v.location ?? "-"}</td>
      <td className="p-4">{v.camera ?? v.cameraName ?? "-"}</td>
      <td className="p-4 text-slate-500">{v.time ?? "-"}</td>
      <td className="p-4">
        <Badge text={status} variant={status} />
      </td>
      <td className="p-4 text-center">
        <div className="flex items-center justify-center">
          {canReview && isReviewable ? (
            <button
              type="button"
              onClick={() => onReview(v)}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold bg-blue-600 text-white hover:bg-blue-700 border border-blue-700 shadow-sm transition-colors w-24 justify-center"
              title="Review & Verify"
            >
              <ClipboardCheck className="w-3.5 h-3.5 shrink-0" />
              Review
            </button>
          ) : (
            <button
              type="button"
              onClick={() => onSelect(v)}
              className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors w-24 justify-center ${
                v.clipUrl
                  ? "bg-blue-50 text-blue-600 hover:bg-blue-100 border border-blue-200"
                  : "bg-slate-50 text-slate-500 hover:bg-slate-100 border border-slate-200"
              }`}
              title={v.clipUrl ? "Watch Recording" : "View Details"}
            >
              {v.clipUrl ? <Video className="w-3.5 h-3.5 shrink-0" /> : <Eye className="w-3.5 h-3.5 shrink-0" />}
              {v.clipUrl ? "Watch Clip" : "Details"}
            </button>
          )}
        </div>
      </td>
    </tr>
  );
}

function TableHead() {
  return (
    <thead className="bg-slate-50 text-slate-600 border-b">
      <tr>
        <th className="p-4 text-left">ID</th>
        <th className="p-4 text-left">Student</th>
        <th className="p-4 text-left">Type</th>
        <th className="p-4 text-left">Severity</th>
        <th className="p-4 text-left">Confidence</th>
        <th className="p-4 text-left">Location</th>
        <th className="p-4 text-left">Camera</th>
        <th className="p-4 text-left">Time</th>
        <th className="p-4 text-left">Status</th>
        <th className="p-4 text-center">Actions</th>
      </tr>
    </thead>
  );
}

export default function ViolationsTableFull() {
  const [violations, setViolations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [selectedViolation, setSelectedViolation] = useState(null);
  const [reviewViolation, setReviewViolation] = useState(null);
  const [typeFilter, setTypeFilter] = useState("all");
  const [statusFilter, setStatusFilter] = useState("all");
  const [search, setSearch] = useState("");

  const canReview = (() => {
    try {
      const u = JSON.parse(localStorage.getItem("user") || "{}");
      const r = u.role;
      return r === "admin" || r === "discipline_incharge" || r === "teacher";
    } catch {
      return false;
    }
  })();

  const fetchViolations = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const data = await apiGet("/api/violations");
      setViolations(data);
      setError("");
    } catch (err) {
      setError(err.message);
    } finally {
      if (!silent) setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchViolations();
    const id = setInterval(() => fetchViolations(true), 30000);
    return () => clearInterval(id);
  }, [fetchViolations]);

  const violationTypes = useMemo(() => {
    const set = new Set();
    for (const v of violations) {
      const t = String(v.type || "").trim().toLowerCase();
      if (t) set.add(t);
    }
    return Array.from(set).sort();
  }, [violations]);

  const filtered = useMemo(() => {
    return violations.filter((v) => {
      const t = String(v.type || "").trim().toLowerCase();
      const st = normStatus(v);
      const name = String(v.student ?? v.studentName ?? "").toLowerCase();
      const roll = String(v.studentRollNumber ?? "").toLowerCase();
      const location = String(v.location ?? "").toLowerCase();
      const q = search.toLowerCase().trim();

      const matchType = typeFilter === "all" || t === typeFilter;
      const matchStatus = statusFilter === "all" || st === statusFilter;
      const matchSearch =
        !q ||
        name.includes(q) ||
        roll.includes(q) ||
        location.includes(q) ||
        String(v._id || v.id).toLowerCase().includes(q);

      return matchType && matchStatus && matchSearch;
    });
  }, [violations, typeFilter, statusFilter, search]);

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

  return (
    <>
      <div className="flex flex-wrap items-center justify-between gap-4 mb-6 bg-white border border-slate-100 rounded-xl p-4 shadow-sm">
        <div className="flex flex-wrap items-center gap-4 flex-1">
          <div className="relative flex-1 min-w-[240px] max-w-[360px]">
            <Search className="absolute left-3 top-2.5 text-slate-400 w-4 h-4" />
            <input
              type="text"
              placeholder="Search student name, SAP ID, location..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-4 py-1.5 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/20"
            />
          </div>

          <div className="flex items-center gap-2 text-sm">
            <span className="text-slate-500 font-semibold flex items-center gap-1">
              <Filter className="w-4 h-4" /> Type:
            </span>
            <select
              value={typeFilter}
              onChange={(e) => setTypeFilter(e.target.value)}
              className="border border-slate-200 rounded-lg px-3 py-1.5 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/20 capitalize min-w-[150px]"
            >
              <option value="all">All Types</option>
              {violationTypes.map((t) => (
                <option key={t} value={t}>
                  {t.replace(/_/g, " ")}
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
          Showing {filtered.length} of {violations.length} violations
        </span>
      </div>

      {filtered.length === 0 ? (
        <div className="bg-slate-50 border border-slate-200 rounded-xl p-8 text-center text-slate-500 text-sm">
          No camera violations match the selected filters.
        </div>
      ) : (
        <div className="bg-white border rounded-xl overflow-hidden shadow-sm">
          <table className="w-full text-sm">
            <TableHead />
            <tbody>
              {filtered.map((v) => (
                <ViolationRow
                  key={v._id || v.id}
                  v={v}
                  onSelect={setSelectedViolation}
                  canReview={canReview}
                  onReview={setReviewViolation}
                />
              ))}
            </tbody>
          </table>
        </div>
      )}

      {selectedViolation && (
        <VideoClipModal
          violation={selectedViolation}
          onClose={() => setSelectedViolation(null)}
        />
      )}

      {reviewViolation && (
        <ApproveViolationModal
          violation={reviewViolation}
          onClose={() => setReviewViolation(null)}
          onDone={() => fetchViolations()}
        />
      )}
    </>
  );
}
