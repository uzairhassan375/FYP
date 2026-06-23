import { Search } from "lucide-react";

export default function StudentsFilters({
  search,
  setSearch,
  departmentFilter,
  setDepartmentFilter,
  departments = [],
}) {
  return (
    <div className="bg-white border rounded-xl p-4 flex flex-wrap gap-4 items-center">
      <div className="relative flex-1 min-w-[250px]">
        <Search className="absolute left-3 top-2.5 text-slate-400" size={18} />
        <input
          placeholder="Search by name or roll number..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full pl-10 pr-4 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/20"
        />
      </div>

      <div className="flex items-center gap-2 text-sm">
        <span className="text-slate-500 font-semibold">Department:</span>
        <select
          value={departmentFilter}
          onChange={(e) => setDepartmentFilter(e.target.value)}
          className="px-4 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500/20 capitalize min-w-[160px]"
        >
          <option value="all">All Departments</option>
          {departments.map((d) => (
            <option key={d} value={d}>
              {d}
            </option>
          ))}
        </select>
      </div>
    </div>
  );
}
