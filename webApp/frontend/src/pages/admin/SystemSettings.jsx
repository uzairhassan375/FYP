import { useCallback, useEffect, useState } from "react";
import { Clock, Loader2, Save, AlertCircle, CheckCircle2 } from "lucide-react";
import Topbar from "../../components/Topbar";
import { apiGet, apiPatch } from "../../lib/api";

export default function SystemSettings() {
  const [minutes, setMinutes] = useState(15);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const data = await apiGet("/api/system-settings");
      setMinutes(Number(data.violationCooldownMinutes) || 15);
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

  const handleSave = async (e) => {
    e.preventDefault();
    setSaving(true);
    setSuccess("");
    setError("");
    try {
      const data = await apiPatch("/api/system-settings", {
        violationCooldownMinutes: Number(minutes),
      });
      setMinutes(Number(data.violationCooldownMinutes) || minutes);
      setSuccess("Cooldown updated. Backend and AI server will use the new value.");
      setTimeout(() => setSuccess(""), 5000);
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <>
      <Topbar />

      <div className="p-6 max-w-2xl">
        <div className="mb-6">
          <h1 className="text-2xl font-bold text-slate-900">System Settings</h1>
          <p className="text-slate-500 mt-1">
            Configure global behaviour for violation detection and automatic fines.
          </p>
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

        <div className="bg-white border rounded-xl shadow-sm overflow-hidden">
          <div className="px-6 py-4 border-b bg-slate-50 flex items-center gap-3">
            <div className="p-2 rounded-lg bg-blue-100 text-blue-600">
              <Clock size={20} />
            </div>
            <div>
              <h2 className="font-semibold text-slate-800">Violation cooldown</h2>
              <p className="text-xs text-slate-500">
                Same student + same violation type within this window will not create another violation or fine.
              </p>
            </div>
          </div>

          {loading ? (
            <div className="p-10 flex justify-center">
              <Loader2 className="w-8 h-8 text-blue-600 animate-spin" />
            </div>
          ) : (
            <form onSubmit={handleSave} className="p-6 space-y-5">
              <div>
                <label
                  htmlFor="cooldown-minutes"
                  className="block text-sm font-medium text-slate-700 mb-2"
                >
                  Cooldown duration (minutes)
                </label>
                <input
                  id="cooldown-minutes"
                  type="number"
                  min={1}
                  max={1440}
                  step={1}
                  value={minutes}
                  onChange={(e) => setMinutes(e.target.value)}
                  className="w-full max-w-xs border border-slate-200 rounded-lg px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
                  required
                />
                <p className="text-xs text-slate-400 mt-2">
                  Allowed range: 1–1440 minutes (24 hours). Default was 15 minutes.
                </p>
              </div>

              <div className="rounded-lg bg-slate-50 border border-slate-100 px-4 py-3 text-sm text-slate-600">
                Applies to live camera detection, mobile AI auto-fines, and the AI pipeline.
                Multiple violations in a single uploaded video are still processed separately.
              </div>

              <button
                type="submit"
                disabled={saving}
                className="inline-flex items-center gap-2 bg-blue-600 text-white px-5 py-2.5 rounded-lg text-sm font-semibold hover:bg-blue-700 disabled:opacity-60"
              >
                {saving ? (
                  <Loader2 className="w-4 h-4 animate-spin" />
                ) : (
                  <Save className="w-4 h-4" />
                )}
                Save settings
              </button>
            </form>
          )}
        </div>
      </div>
    </>
  );
}
