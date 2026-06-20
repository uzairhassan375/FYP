import {
  PieChart,
  Pie,
  Cell,
  ResponsiveContainer,
  Tooltip,
  Legend,
} from "recharts";

function buildChartData(data) {
  const rows = (data || []).map((d) => ({
    name: d.name,
    value: Number(d.value) || 0,
    color: d.color,
  }));
  const total = rows.reduce((sum, r) => sum + r.value, 0);
  return rows.map((r) => ({
    ...r,
    percent: total > 0 ? Math.round((r.value / total) * 100) : 0,
  }));
}

function legendFormatter(value, entry) {
  const { value: count, percent } = entry.payload;
  return (
    <span className="text-sm text-slate-700">
      {value}{" "}
      <span className="text-slate-500">
        — {count} ({percent}%)
      </span>
    </span>
  );
}

export default function SeverityDonutChart({ data }) {
  const chartData = buildChartData(data);
  const total = chartData.reduce((sum, r) => sum + r.value, 0);

  return (
    <div className="bg-white border rounded-xl p-6">
      <h3 className="text-lg font-semibold mb-4">Severity Distribution</h3>

      {total === 0 ? (
        <p className="text-sm text-slate-500 py-16 text-center">
          No violation data yet.
        </p>
      ) : (
        <ResponsiveContainer width="100%" height={280}>
          <PieChart margin={{ top: 4, right: 4, bottom: 4, left: 4 }}>
            <Pie
              data={chartData.filter((d) => d.value > 0)}
              innerRadius={55}
              outerRadius={85}
              dataKey="value"
              cx="50%"
              cy="42%"
              paddingAngle={chartData.filter((d) => d.value > 0).length > 1 ? 3 : 0}
              label={false}
              labelLine={false}
            >
              {chartData
                .filter((d) => d.value > 0)
                .map((entry, i) => (
                  <Cell
                    key={i}
                    fill={entry.color}
                    stroke="#fff"
                    strokeWidth={2}
                  />
                ))}
            </Pie>
            <Tooltip
              formatter={(value, name, props) => [
                `${value} violation${value !== 1 ? "s" : ""} (${props.payload.percent}%)`,
                name,
              ]}
            />
            <Legend
              verticalAlign="bottom"
              align="center"
              iconType="circle"
              iconSize={10}
              wrapperStyle={{ paddingTop: 12 }}
              formatter={legendFormatter}
              payload={chartData.map((entry) => ({
                value: entry.name,
                type: "circle",
                color: entry.color,
                payload: entry,
              }))}
            />
          </PieChart>
        </ResponsiveContainer>
      )}
    </div>
  );
}
