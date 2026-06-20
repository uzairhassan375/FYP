import { useState, useEffect } from "react";
import { X, Loader2 } from "lucide-react";
import { apiPost } from "../lib/api";
import { AI_VIOLATION_PRESETS, presetForViolationKey } from "../data/violationTypes";

const SEVERITIES = ["LOW", "MED", "HIGH"];

export default function AddRuleModal({ onClose, onSaved }) {
  const [title, setTitle] = useState("");
  const [violationType, setViolationType] = useState(AI_VIOLATION_PRESETS[0].key);
  const [severity, setSeverity] = useState("MED");
  const [penalty, setPenalty] = useState(0);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    const preset = presetForViolationKey(AI_VIOLATION_PRESETS[0].key);
    if (preset) {
      setTitle(preset.title);
      setSeverity(preset.severity);
    }
  }, []);

  useEffect(() => {
    const handleEscape = (e) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", handleEscape);
    return () => window.removeEventListener("keydown", handleEscape);
  }, [onClose]);

  const handleViolationTypeChange = (nextKey) => {
    setViolationType(nextKey);
    const preset = presetForViolationKey(nextKey);
    if (preset) {
      setTitle(preset.title);
      setSeverity(preset.severity);
    }
  };

  const selectedPreset = presetForViolationKey(violationType);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setSaving(true);
    setError("");
    try {
      await apiPost("/api/policy-rules", {
        title: title.trim() || selectedPreset?.title || "Rule",
        violation_type: violationType.trim().toLowerCase(),
        severity,
        penalty,
      });
      onSaved?.();
      onClose();
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50" onClick={onClose}>
      <div
        className="bg-white rounded-2xl shadow-xl max-w-md w-full p-6"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-xl font-bold">Add Policy Rule</h2>
          <button
            type="button"
            onClick={onClose}
            className="p-2 rounded-lg hover:bg-slate-100 text-slate-500"
          >
            <X size={20} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1">
              Violation Type (AI key)
            </label>
            <select
              value={violationType}
              onChange={(e) => handleViolationTypeChange(e.target.value)}
              required
              className="w-full border rounded-lg px-4 py-2 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              {AI_VIOLATION_PRESETS.map((preset) => (
                <option key={preset.key} value={preset.key}>
                  {preset.key} — {preset.title}
                </option>
              ))}
            </select>
            {selectedPreset && (
              <p className="mt-1 text-xs text-slate-400">
                AI also matches: <span className="font-mono">{selectedPreset.aliases}</span>
              </p>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1">Title</label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              required
              className="w-full border rounded-lg px-4 py-2 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              placeholder="e.g. Gun Detected"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1">Severity</label>
            <select
              value={severity}
              onChange={(e) => setSeverity(e.target.value)}
              className="w-full border rounded-lg px-4 py-2 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              {SEVERITIES.map((s) => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1">Penalty (Rs.)</label>
            <input
              type="number"
              min={0}
              value={penalty}
              onChange={(e) => setPenalty(Number(e.target.value) || 0)}
              className="w-full border rounded-lg px-4 py-2 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
            <p className="mt-1 text-xs text-slate-400">
              Pending fines linked to this rule update automatically when you change the penalty.
            </p>
          </div>

          {error && (
            <p className="text-sm text-red-600">{error}</p>
          )}

          <div className="flex gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 border rounded-lg py-2.5 hover:bg-slate-50 font-medium"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={saving}
              className="flex-1 bg-blue-600 text-white rounded-lg py-2.5 hover:bg-blue-700 disabled:opacity-50 flex items-center justify-center gap-2 font-medium"
            >
              {saving ? <><Loader2 className="animate-spin" size={18} /> Saving...</> : "Add Rule"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
