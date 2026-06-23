import { Eye, User, Pencil, Trash2, GraduationCap, Mail } from "lucide-react";

export default function StudentCard({ student, onViewDetails, onEdit, onDelete }) {
  const id = student._id || student.id;

  return (
    <div className="group bg-white border border-slate-100 hover:border-blue-200 rounded-2xl p-5 flex flex-col shadow-sm hover:shadow-md transition-all duration-300 relative overflow-hidden">
      {/* Top accent bar */}
      <div className="absolute top-0 left-0 right-0 h-1.5 bg-gradient-to-r from-blue-600 to-indigo-600 opacity-80" />

      <div className="flex items-center gap-4 mt-1">
        {student.avatar ? (
          <img
            src={student.avatar}
            alt={student.name}
            className="w-14 h-14 rounded-2xl object-cover border-2 border-slate-100 group-hover:border-blue-200 transition-colors shadow-sm"
          />
        ) : (
          <div className="w-14 h-14 rounded-2xl bg-gradient-to-br from-slate-50 to-slate-100 flex items-center justify-center border border-slate-200/60 shadow-inner">
            <User className="text-slate-400 w-6 h-6" />
          </div>
        )}

        <div className="flex-1 min-w-0">
          <div className="font-bold text-slate-800 text-base truncate group-hover:text-blue-600 transition-colors">
            {student.name}
          </div>
          <div className="text-xs font-semibold text-blue-600 bg-blue-50 px-2 py-0.5 rounded-md inline-block mt-1">
            {student.rollNumber || student.roll_number}
          </div>
        </div>
      </div>

      {/* Info Rows */}
      <div className="mt-5 space-y-2.5 flex-1">
        {student.department && (
          <div className="flex items-center gap-2 text-xs text-slate-600">
            <GraduationCap size={15} className="text-slate-400" />
            <span className="truncate capitalize">{student.department} Department</span>
          </div>
        )}
        <div className="flex items-center gap-2 text-xs text-slate-500">
          <Mail size={15} className="text-slate-400" />
          <span className="truncate">{student.email || "No email"}</span>
        </div>
      </div>

      <div className="mt-5 pt-4 border-t border-slate-50 flex items-center justify-between">
        <div className="text-[10px] font-bold text-slate-400 uppercase tracking-widest">
          Registered ID
        </div>
        <div className="text-[10px] font-mono text-slate-400 font-medium">
          {String(id).slice(-8).toUpperCase()}
        </div>
      </div>

      <div className="mt-5 flex gap-2">
        <button
          type="button"
          onClick={() => onViewDetails?.(student)}
          className="flex-1 flex items-center justify-center gap-1.5 bg-slate-50 hover:bg-blue-50 hover:text-blue-600 text-slate-700 rounded-xl py-2.5 text-xs font-bold transition-all active:scale-[0.98]"
        >
          <Eye size={14} /> View Details
        </button>
        <button
          type="button"
          onClick={() => onEdit?.(student)}
          className="flex items-center justify-center gap-1.5 border border-slate-200 hover:bg-slate-50 hover:border-slate-300 text-slate-700 rounded-xl px-3 py-2.5 text-xs font-bold transition-all active:scale-[0.98]"
        >
          <Pencil size={14} /> Edit
        </button>
        <button
          type="button"
          onClick={() => onDelete?.(student)}
          className="flex items-center justify-center gap-1.5 border border-red-100 hover:bg-red-50 text-red-500 rounded-xl px-3 py-2.5 text-xs font-bold transition-all active:scale-[0.98]"
          title="Delete student"
        >
          <Trash2 size={14} />
        </button>
      </div>
    </div>
  );
}
