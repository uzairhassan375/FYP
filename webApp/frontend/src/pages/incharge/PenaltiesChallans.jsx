import { useState, useEffect, useCallback, useMemo } from "react";
import { Bell, FileText, Receipt, CheckCircle, Loader2, AlertCircle, RefreshCw } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { Card, CardContent } from "../../components/Card";
import { apiGet, apiPatch } from "../../lib/api";

const POLL_INTERVAL = 30000;

function statusColor(status) {
  if (status === "Paid") return "bg-green-100 text-green-600";
  if (status === "Waived") return "bg-slate-100 text-slate-500";
  return "bg-red-100 text-red-600";
}

export default function PenaltiesChallans() {
  const navigate = useNavigate();
  const [fines, setFines] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [updating, setUpdating] = useState(null);
  const [typeFilter, setTypeFilter] = useState("all");
  const [statusFilter, setStatusFilter] = useState("all");

  const fetchFines = useCallback(async () => {
    try {
      const data = await apiGet("/api/fines");
      setFines(data);
      setError("");
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchFines();
    const interval = setInterval(fetchFines, POLL_INTERVAL);
    return () => clearInterval(interval);
  }, [fetchFines]);

  const markPaid = async (fine) => {
    setUpdating(fine._id || fine.id);
    try {
      const updated = await apiPatch(`/api/fines/${fine._id || fine.id}`, { status: "Paid" });
      setFines((prev) =>
        prev.map((f) => (f._id === updated._id || f.id === updated.id ? updated : f))
      );
    } catch (err) {
      setError(err.message);
    } finally {
      setUpdating(null);
    }
  };

  const markWaived = async (fine) => {
    setUpdating(fine._id || fine.id);
    try {
      const updated = await apiPatch(`/api/fines/${fine._id || fine.id}`, { status: "Waived" });
      setFines((prev) =>
        prev.map((f) => (f._id === updated._id || f.id === updated.id ? updated : f))
      );
    } catch (err) {
      setError(err.message);
    } finally {
      setUpdating(null);
    }
  };

  // Computed summary
  const totalFines = fines.length;
  const pendingFines = fines.filter((f) => f.status === "Pending");
  const paidFines = fines.filter((f) => f.status === "Paid");
  const pendingAmount = pendingFines.reduce((sum, f) => sum + (f.amount || 0), 0);

  const violationTypes = useMemo(() => {
    const set = new Set();
    for (const f of fines) {
      const type = f.violationType || f.violation_type;
      const t = type ? String(type).trim().toLowerCase() : "";
      if (t) set.add(t);
    }
    return Array.from(set).sort();
  }, [fines]);

  const filteredFines = useMemo(() => {
    return fines.filter((f) => {
      const type = f.violationType || f.violation_type;
      const t = type ? String(type).trim().toLowerCase() : "";
      const s = String(f.status || "").trim();

      const matchType = typeFilter === "all" || t === typeFilter;
      const matchStatus = statusFilter === "all" || s === statusFilter;

      return matchType && matchStatus;
    });
  }, [fines, typeFilter, statusFilter]);

  const summaryCards = [
    { title: "Total Fines", value: totalFines, icon: Receipt, color: "text-blue-600" },
    { title: "Pending Amount", value: `Rs. ${pendingAmount.toLocaleString()}`, icon: Receipt, color: "text-red-500" },
    { title: "Fines Issued", value: totalFines, icon: FileText, color: "text-blue-600" },
    { title: "Pending Fines", value: pendingFines.length, icon: FileText, color: "text-orange-500" },
  ];

  return (
    <>
      {/* Header */}
      <div className="flex justify-between items-center mb-6">
        <div>
          <h1 className="text-2xl font-semibold">Penalties & Challans</h1>
          <p className="text-slate-500">Manage payment status and challans</p>
        </div>
        <div className="flex items-center gap-4">
          <button
            onClick={fetchFines}
            className="p-2 rounded-lg hover:bg-slate-100 text-slate-500 transition-colors"
            title="Refresh"
          >
            <RefreshCw className="w-5 h-5" />
          </button>
          <button
            onClick={() => navigate("/incharge/notifications")}
            className="p-2 rounded-lg hover:bg-slate-100 text-slate-500 transition-colors"
            title="Notifications"
          >
            <Bell className="w-6 h-6" />
          </button>
          <div className="w-8 h-8 rounded-full bg-blue-600 text-white flex items-center justify-center font-medium">
            S
          </div>
        </div>
      </div>

      {error && (
        <div className="mb-4 bg-red-50 border border-red-200 rounded-xl p-4 flex items-center gap-3 text-red-600">
          <AlertCircle className="shrink-0" size={18} />
          <p className="text-sm">{error}</p>
        </div>
      )}

      <div className="space-y-6">
        {/* Summary Cards */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
          {summaryCards.map((card) => (
            <Card key={card.title}>
              <CardContent className="flex flex-col items-center justify-center h-36">
                <card.icon className={`w-8 h-8 mb-2 ${card.color}`} />
                <p className="text-slate-500 text-sm">{card.title}</p>
                <p className="text-2xl font-bold">{card.value}</p>
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Fines Table */}
        <Card>
          <CardContent>
            {/* Filter Bar */}
            <div className="flex flex-col gap-4 md:flex-row md:items-center justify-between mb-6 pb-4 border-b border-slate-100">
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-semibold">Fines List</h2>
                {loading && <Loader2 className="w-4 h-4 text-blue-600 animate-spin" />}
                {!loading && (
                  <span className="text-xs text-slate-400">
                    Showing {filteredFines.length} of {fines.length}
                  </span>
                )}
              </div>

              <div className="flex flex-wrap items-center gap-4">
                <div className="flex items-center gap-2 text-sm">
                  <span className="text-slate-500 font-medium">Violation Type:</span>
                  <select
                    value={typeFilter}
                    onChange={(e) => setTypeFilter(e.target.value)}
                    className="border border-slate-200 rounded-lg px-3 py-1.5 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/20 capitalize"
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
                  <span className="text-slate-500 font-medium">Status:</span>
                  <select
                    value={statusFilter}
                    onChange={(e) => setStatusFilter(e.target.value)}
                    className="border border-slate-200 rounded-lg px-3 py-1.5 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/20"
                  >
                    <option value="all">All Statuses</option>
                    <option value="Pending">Pending</option>
                    <option value="Paid">Paid</option>
                    <option value="Waived">Waived</option>
                  </select>
                </div>
              </div>
            </div>

            {loading && fines.length === 0 ? (
              <div className="flex items-center justify-center py-12">
                <Loader2 className="w-8 h-8 text-blue-600 animate-spin" />
              </div>
            ) : fines.length === 0 ? (
              <div className="text-center py-12 text-slate-400">
                <Receipt className="w-12 h-12 mx-auto mb-3 opacity-30" />
                <p>No fines issued yet. Fines are applied automatically when a student violates a policy rule.</p>
              </div>
            ) : filteredFines.length === 0 ? (
              <div className="text-center py-12 text-slate-400">
                <Receipt className="w-12 h-12 mx-auto mb-3 opacity-30" />
                <p>No fines match the selected filters.</p>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-left text-slate-500 border-b">
                    <tr className="h-10">
                      <th className="font-medium p-2">Fine ID</th>
                      <th className="font-medium p-2">Student</th>
                      <th className="font-medium p-2">Violation Type</th>
                      <th className="font-medium p-2">Amount</th>
                      <th className="font-medium p-2">Date</th>
                      <th className="font-medium p-2">Status</th>
                      <th className="font-medium p-2">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y">
                    {filteredFines.map((fine) => {
                      const fineId = fine._id || fine.id;
                      const isUpdating = updating === fineId;
                      return (
                        <tr key={fineId} className="h-14 hover:bg-slate-50 transition-colors">
                          <td className="font-mono text-xs text-slate-500 p-2">
                            {String(fineId).slice(0, 8)}…
                          </td>
                          <td className="font-medium p-2">{fine.studentName || "Unknown"}</td>
                          <td className="p-2 capitalize">
                            {(fine.violationType || fine.violation_type || "—").replace(/_/g, " ")}
                          </td>
                          <td className="p-2 font-bold text-blue-700">Rs. {(fine.amount || 0).toLocaleString()}</td>
                          <td className="text-slate-500 p-2">{fine.time || "—"}</td>
                          <td className="p-2">
                            <span className={`px-3 py-1 rounded-full text-xs font-medium ${statusColor(fine.status)}`}>
                              {fine.status}
                            </span>
                          </td>
                          <td className="p-2">
                            {fine.status === "Pending" && (
                              <div className="flex gap-1">
                                <button
                                  onClick={() => markPaid(fine)}
                                  disabled={isUpdating}
                                  className="flex items-center gap-1.5 px-2.5 py-1.5 text-xs bg-green-600 hover:bg-green-700 text-white rounded-lg transition-colors disabled:opacity-50"
                                >
                                  {isUpdating ? <Loader2 className="w-3 h-3 animate-spin" /> : <CheckCircle className="w-3 h-3" />}
                                  Paid
                                </button>
                                <button
                                  onClick={() => markWaived(fine)}
                                  disabled={isUpdating}
                                  className="flex items-center gap-1.5 px-2.5 py-1.5 text-xs bg-slate-200 hover:bg-slate-300 text-slate-700 rounded-lg transition-colors disabled:opacity-50"
                                >
                                  Waive
                                </button>
                              </div>
                            )}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}

            <p className="mt-4 text-xs text-slate-400 text-right">
              Auto-refreshes every 30 seconds · Total collected: Rs. {paidFines.reduce((s, f) => s + (f.amount || 0), 0).toLocaleString()}
            </p>
          </CardContent>
        </Card>
      </div>
    </>
  );
}
