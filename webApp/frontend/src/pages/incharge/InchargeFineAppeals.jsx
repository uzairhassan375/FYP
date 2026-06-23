import { useState, useEffect, useCallback } from "react";
import {
  MessageSquare,
  Loader2,
  AlertCircle,
  RefreshCw,
  CheckCircle,
  XCircle,
} from "lucide-react";
import { apiGet, apiPatch } from "../../lib/api";

const STATUS_FILTERS = [
  { id: "", label: "All" },
  { id: "pending", label: "Pending" },
  { id: "approved", label: "Approved" },
  { id: "rejected", label: "Rejected" },
];

function statusBadge(status) {
  const s = String(status || "").toLowerCase();
  if (s === "approved") return "bg-green-100 text-green-700";
  if (s === "rejected") return "bg-red-100 text-red-700";
  return "bg-amber-100 text-amber-800";
}

export default function InchargeFineAppeals() {
  const [appeals, setAppeals] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [filter, setFilter] = useState("pending");
  const [acting, setActing] = useState(null);
  const [reviewNote, setReviewNote] = useState("");
  const [selected, setSelected] = useState(null);

  const load = useCallback(async () => {
    try {
      const q = filter ? `?status=${filter}` : "";
      const data = await apiGet(`/api/fine-appeals${q}`);
      setAppeals(data);
      setError("");
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, [filter]);

  useEffect(() => {
    setLoading(true);
    load();
    const t = setInterval(load, 30000);
    return () => clearInterval(t);
  }, [load]);

  const resolve = async (appeal, status) => {
    const id = appeal._id || appeal.id;
    setActing(id);
    setError("");
    try {
      await apiPatch(`/api/fine-appeals/${id}`, {
        status,
        reviewNote: reviewNote.trim() || undefined,
      });
      setSelected(null);
      setReviewNote("");
      await load();
    } catch (err) {
      setError(err.message);
    } finally {
      setActing(null);
    }
  };

  const pendingCount = appeals.filter((a) => a.status === "pending").length;

  return (
    <div className="p-6 space-y-6">
      <div className="flex flex-wrap justify-between items-start gap-4">
        <div>
          <h1 className="text-2xl font-bold">Fine Appeals</h1>
          <p className="text-slate-500">
            Review student appeals — approve to waive the fine if unjustified
          </p>
        </div>
        <button
          type="button"
          onClick={load}
          className="p-2 rounded-lg hover:bg-slate-100 text-slate-500"
        >
          <RefreshCw size={18} />
        </button>
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 flex items-center gap-3 text-red-600 text-sm">
          <AlertCircle size={18} />
          {error}
        </div>
      )}

      <div className="flex flex-wrap gap-2">
        {STATUS_FILTERS.map(({ id, label }) => (
          <button
            key={id || "all"}
            type="button"
            onClick={() => setFilter(id)}
            className={`px-4 py-2 rounded-lg text-sm font-medium ${
              filter === id
                ? "bg-blue-600 text-white"
                : "bg-slate-100 text-slate-600 hover:bg-slate-200"
            }`}
          >
            {label}
            {id === "pending" && filter === "pending" && pendingCount > 0
              ? ` (${pendingCount})`
              : ""}
          </button>
        ))}
      </div>

      {loading && appeals.length === 0 ? (
        <div className="flex justify-center py-16">
          <Loader2 className="w-10 h-10 text-blue-600 animate-spin" />
        </div>
      ) : appeals.length === 0 ? (
        <div className="bg-white border rounded-xl p-12 text-center text-slate-500">
          <MessageSquare className="w-12 h-12 mx-auto mb-3 opacity-30" />
          <p>No appeals in this filter.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {appeals.map((appeal) => {
            const id = appeal._id || appeal.id;
            const fine = appeal.fine;
            const isOpen = selected === id;
            const isPending = appeal.status === "pending";
            return (
              <div key={id} className="bg-white border rounded-xl p-5 shadow-sm">
                <div className="flex flex-wrap justify-between gap-3">
                  <div>
                    <div className="flex items-center gap-2 flex-wrap">
                      <h3 className="font-semibold text-lg">
                        {appeal.studentName || "Student"}
                      </h3>
                      <span
                        className={`px-2.5 py-0.5 rounded-full text-xs font-medium capitalize ${statusBadge(appeal.status)}`}
                      >
                        {appeal.status}
                      </span>
                    </div>
                    <p className="text-sm text-slate-500 mt-1">
                      Submitted {appeal.time || "—"}
                      {fine
                        ? ` · Fine: Rs. ${(fine.amount || 0).toLocaleString()} (${fine.violationType || fine.violation_type || "—"})`
                        : ""}
                    </p>
                  </div>
                  {isPending && (
                    <button
                      type="button"
                      onClick={() => {
                        setSelected(isOpen ? null : id);
                        setReviewNote("");
                      }}
                      className="text-sm text-blue-600 font-medium hover:underline"
                    >
                      {isOpen ? "Close" : "Review"}
                    </button>
                  )}
                </div>

                <div className="mt-3 p-3 bg-slate-50 rounded-lg text-sm text-slate-700">
                  <span className="font-medium text-slate-500">Student message: </span>
                  {appeal.message}
                </div>

                {appeal.reviewNote && (
                  <p className="mt-2 text-sm text-slate-600">
                    <span className="font-medium">Staff note:</span> {appeal.reviewNote}
                    {appeal.reviewedByName ? ` — ${appeal.reviewedByName}` : ""}
                  </p>
                )}

                {isOpen && isPending && (
                  <div className="mt-4 pt-4 border-t space-y-3">
                    <textarea
                      value={reviewNote}
                      onChange={(e) => setReviewNote(e.target.value)}
                      placeholder="Optional note for the student (e.g. why waived or rejected)"
                      rows={2}
                      className="w-full border rounded-lg px-3 py-2 text-sm"
                    />
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        disabled={acting === id}
                        onClick={() => resolve(appeal, "approved")}
                        className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white rounded-lg text-sm font-medium hover:bg-green-700 disabled:opacity-50"
                      >
                        {acting === id ? (
                          <Loader2 className="w-4 h-4 animate-spin" />
                        ) : (
                          <CheckCircle size={16} />
                        )}
                        Approve & waive fine
                      </button>
                      <button
                        type="button"
                        disabled={acting === id}
                        onClick={() => resolve(appeal, "rejected")}
                        className="flex items-center gap-2 px-4 py-2 bg-slate-200 text-slate-800 rounded-lg text-sm font-medium hover:bg-slate-300 disabled:opacity-50"
                      >
                        <XCircle size={16} />
                        Reject appeal
                      </button>
                    </div>
                    <p className="text-xs text-slate-400">
                      Approving sets the linked fine to <strong>Waived</strong>. Rejecting keeps the fine pending.
                    </p>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
