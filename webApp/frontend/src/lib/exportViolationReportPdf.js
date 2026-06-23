import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";

/**
 * Download a violation summary report as PDF.
 * @param {object} report - from GET /api/reports/violations
 */
export function downloadViolationReportPdf(report) {
  const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
  const generated = report.generatedAt
    ? new Date(report.generatedAt).toLocaleString()
    : new Date().toLocaleString();

  doc.setFontSize(18);
  doc.text("HawkEye — Violation Report", 14, 18);
  doc.setFontSize(10);
  doc.setTextColor(100);
  doc.text(`Generated: ${generated}`, 14, 26);
  doc.setTextColor(0);

  doc.setFontSize(11);
  doc.text(
    `Total violations: ${report.totals?.violations ?? 0}  |  Total fines: ${report.totals?.fines ?? 0}  |  Students: ${report.totals?.studentsWithViolations ?? 0}`,
    14,
    34,
  );

  let startY = 42;

  autoTable(doc, {
    startY,
    head: [["Rank", "Student", "Department", "Violations", "Fines", "Fine amount (Rs.)"]],
    body: (report.topStudents || []).map((s, i) => [
      i + 1,
      s.studentName || "—",
      s.department || "—",
      s.violationCount ?? 0,
      s.fineCount ?? 0,
      (s.totalFineAmount ?? 0).toLocaleString(),
    ]),
    theme: "striped",
    headStyles: { fillColor: [33, 150, 243] },
    margin: { left: 14, right: 14 },
  });

  startY = doc.lastAutoTable.finalY + 12;
  doc.setFontSize(13);
  doc.text("By violation type", 14, startY);

  autoTable(doc, {
    startY: startY + 4,
    head: [["Violation type", "Count"]],
    body: (report.byViolationType || []).map((r) => [
      r.type || "—",
      r.count ?? 0,
    ]),
    theme: "grid",
    headStyles: { fillColor: [99, 102, 241] },
    margin: { left: 14, right: 14 },
  });

  startY = doc.lastAutoTable.finalY + 12;
  doc.setFontSize(13);
  doc.text("By department", 14, startY);

  autoTable(doc, {
    startY: startY + 4,
    head: [["Department", "Violations"]],
    body: (report.byDepartment || []).map((r) => [
      r.department || "—",
      r.count ?? 0,
    ]),
    theme: "grid",
    headStyles: { fillColor: [76, 175, 80] },
    margin: { left: 14, right: 14 },
  });

  if ((report.finesByViolationType || []).length > 0) {
    startY = doc.lastAutoTable.finalY + 12;
    if (startY > 250) {
      doc.addPage();
      startY = 18;
    }
    doc.setFontSize(13);
    doc.text("Fines by violation type", 14, startY);
    autoTable(doc, {
      startY: startY + 4,
      head: [["Type", "Fine count", "Total Rs."]],
      body: report.finesByViolationType.map((r) => [
        r.type || "—",
        r.count ?? 0,
        (r.totalAmount ?? 0).toLocaleString(),
      ]),
      theme: "grid",
      headStyles: { fillColor: [244, 67, 54] },
      margin: { left: 14, right: 14 },
    });
  }

  doc.save(`hawkeye-violation-report-${Date.now()}.pdf`);
}
