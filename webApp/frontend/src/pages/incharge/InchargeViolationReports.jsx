import { useState, useEffect, useCallback } from "react";
import {
  BarChart2,
  Download,
  Loader2,
  AlertCircle,
  RefreshCw,
  Users,
  Building2,
  ShieldAlert,
} from "lucide-react";
import { apiGet } from "../../lib/api";
import { downloadViolationReportPdf } from "../../lib/exportViolationReportPdf";

const TABS = [
  { id: "students", label: "Top students", icon: Users },
  { id: "type", label: "By violation type", icon: ShieldAlert },
  { id: "department", label: "By department", icon: Building2 },
];

export default function InchargeViolationReports() {
  const [report, setReport] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [tab, setTab] = useState("students");
  const [exporting, setExporting] = useState(false);

  const load = useCallback(async () => {
    try {
      const data = await apiGet("/api/reports/violations");
      setReport(data);
      setError("");
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const handlePdf = () => {
    if (!report) return;
    setExporting(true);
    try {
      downloadViolationReportPdf(report);
    } finally {
      setTimeout(() => setExporting(false), 500);
    }
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex flex-wrap justify-between items-start gap-4">
        <div>
          <h1 className="text-2xl font-bold">Violation Reports</h1>
          <p className="text-slate-500">
            Students with the most violations, grouped by type and department
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={load}
            className="p-2 rounded-lg hover:bg-slate-100 text-slate-500"
            title="Refresh"
          >
            <RefreshCw size={18} />
          </button>
          <button
            type="button"
            onClick={handlePdf}
            disabled={!report || exporting}
            className="flex items-center gap-2 bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700 disabled:opacity-50"
          >
            {exporting ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : (
              <Download size={16} />
            )}
            Download PDF
          </button>
        </div>
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 flex items-center gap-3 text-red-600 text-sm">
          <AlertCircle className="shrink-0" size={18} />
          {error}
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-20">
          <Loader2 className="w-10 h-10 text-blue-600 animate-spin" />
        </div>
      ) : report ? (
        <>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="bg-white border rounded-xl p-5 flex items-center gap-4">
              <BarChart2 className="text-blue-600" size={28} />
              <div>
                <p className="text-sm text-slate-500">Total violations</p>
                <p className="text-2xl font-bold">{report.totals?.violations ?? 0}</p>
              </div>
            </div>
            <div className="bg-white border rounded-xl p-5 flex items-center gap-4">
              <ShieldAlert className="text-red-500" size={28} />
              <div>
                <p className="text-sm text-slate-500">Total fines issued</p>
                <p className="text-2xl font-bold">{report.totals?.fines ?? 0}</p>
              </div>
            </div>
            <div className="bg-white border rounded-xl p-5 flex items-center gap-4">
              <Users className="text-green-600" size={28} />
              <div>
                <p className="text-sm text-slate-500">Students involved</p>
                <p className="text-2xl font-bold">
                  {report.totals?.studentsWithViolations ?? 0}
                </p>
              </div>
            </div>
          </div>

          <div className="flex flex-wrap gap-2 border-b pb-2">
            {TABS.map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                type="button"
                onClick={() => setTab(id)}
                className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                  tab === id
                    ? "bg-blue-600 text-white"
                    : "bg-slate-100 text-slate-600 hover:bg-slate-200"
                }`}
              >
                <Icon size={16} />
                {label}
              </button>
            ))}
          </div>

          <div className="bg-white border rounded-xl overflow-hidden">
            {tab === "students" && (
              <ReportTable
                empty="No student violations recorded yet."
                headers={["#", "Student", "Department", "Violations", "Fines", "Fine total"]}
                rows={(report.topStudents || []).map((s, i) => [
                  i + 1,
                  s.studentName,
                  s.department,
                  s.violationCount,
                  s.fineCount,
                  `Rs. ${(s.totalFineAmount || 0).toLocaleString()}`,
                ])}
              />
            )}
            {tab === "type" && (
              <ReportTable
                empty="No violations by type."
                headers={["Violation type", "Count"]}
                rows={(report.byViolationType || []).map((r) => [
                  r.type,
                  r.count,
                ])}
              />
            )}
            {tab === "department" && (
              <ReportTable
                empty="No department data."
                headers={["Department", "Violations"]}
                rows={(report.byDepartment || []).map((r) => [
                  r.department,
                  r.count,
                ])}
              />
            )}
          </div>
        </>
      ) : null}
    </div>
  );
}

function ReportTable({ headers, rows, empty }) {
  if (!rows.length) {
    return <p className="p-8 text-center text-slate-500">{empty}</p>;
  }
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="bg-slate-50 text-slate-600 border-b">
          <tr>
            {headers.map((h) => (
              <th key={h} className="text-left p-3 font-semibold">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y">
          {rows.map((row, i) => (
            <tr key={i} className="hover:bg-slate-50">
              {row.map((cell, j) => (
                <td
                  key={j}
                  className={`p-3 ${j === 0 && headers[0] === "#" ? "text-slate-400" : ""} ${typeof cell === "string" && cell.startsWith("Rs.") ? "font-semibold text-blue-700" : ""}`}
                >
                  {typeof cell === "string" ? cell : String(cell)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
