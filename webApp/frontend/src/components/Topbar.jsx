import { Bell, LogOut } from "lucide-react";
import { useNavigate } from "react-router-dom";

export default function Topbar() {
  const navigate = useNavigate();
  const user = JSON.parse(localStorage.getItem("user") || "{}");

  const handleLogout = () => {
    localStorage.removeItem("token");
    localStorage.removeItem("user");
    navigate("/login");
  };

  const handleBellClick = () => {
    if (user.role === "admin") {
      navigate("/notifications");
    } else if (user.role === "student") {
      navigate("/student/notifications");
    } else {
      navigate("/incharge/notifications");
    }
  };

  return (
    <div className="flex items-center justify-between px-6 py-4 bg-white border-b sticky top-0 z-40">
      <div />

      <div className="flex items-center gap-6 ml-4">
        <button
          onClick={handleBellClick}
          className="text-slate-400 hover:text-blue-600 transition-colors"
          title="Notifications"
        >
          <Bell size={20} />
        </button>

        <div className="flex items-center gap-3 pl-6 border-l">
          <div className="text-right hidden sm:block">
            <p className="text-sm font-bold text-slate-800 leading-none">{user.name || "Guest"}</p>
            <p className="text-[10px] font-bold text-slate-400 uppercase tracking-wider mt-1">{user.role || "Unknown"}</p>
          </div>
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-blue-600 to-indigo-700 text-white flex items-center justify-center font-bold shadow-lg shadow-blue-200">
            {(user.name || "U")[0]}
          </div>
          <button
            onClick={handleLogout}
            className="p-2 text-slate-400 hover:text-red-500 hover:bg-red-50 rounded-xl transition-all"
            title="Logout"
          >
            <LogOut size={18} />
          </button>
        </div>
      </div>
    </div>
  );
}
