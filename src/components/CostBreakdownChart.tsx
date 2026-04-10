import { BarChart, Bar, XAxis, YAxis, ResponsiveContainer, Cell, Tooltip } from 'recharts';

interface CostBreakdownChartProps {
  costsByType: {
    materials: number;
    labor: number;
    equipment: number;
    subcontractors: number;
  };
}

const COLORS = [
  'hsl(43, 96%, 56%)',    // materials - primary yellow
  'hsl(187, 92%, 48%)',   // labor - cyan
  'hsl(25, 95%, 53%)',    // equipment - orange
  'hsl(280, 65%, 60%)',   // subcontractors - purple
];

export default function CostBreakdownChart({ costsByType }: CostBreakdownChartProps) {
  const data = [
    { name: 'Materials', value: costsByType.materials, fill: COLORS[0] },
    { name: 'Labor', value: costsByType.labor, fill: COLORS[1] },
    { name: 'Equipment', value: costsByType.equipment, fill: COLORS[2] },
    { name: 'Subcontractors', value: costsByType.subcontractors, fill: COLORS[3] },
  ];

  const total = Object.values(costsByType).reduce((sum, val) => sum + val, 0);

  const formatCurrency = (value: number) => {
    return new Intl.NumberFormat('en-KE', {
      style: 'currency',
      currency: 'KES',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    }).format(value);
  };

  if (total === 0) {
    return (
      <div className="h-64 flex items-center justify-center text-muted-foreground">
        No costs recorded yet
      </div>
    );
  }

  return (
    <div className="h-64">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart
          data={data}
          layout="vertical"
          margin={{ top: 0, right: 0, bottom: 0, left: 0 }}
        >
          <XAxis type="number" hide />
          <YAxis
            type="category"
            dataKey="name"
            axisLine={false}
            tickLine={false}
            width={100}
            tick={{ fill: 'hsl(215, 20%, 55%)', fontSize: 12 }}
          />
          <Tooltip
            cursor={{ fill: 'hsl(220, 14%, 16%)' }}
            contentStyle={{
              backgroundColor: 'hsl(220, 18%, 11%)',
              border: '1px solid hsl(220, 13%, 20%)',
              borderRadius: '8px',
              boxShadow: '0 4px 20px -4px rgba(0,0,0,0.5)',
            }}
            labelStyle={{ color: 'hsl(214, 32%, 91%)', fontWeight: 600 }}
            formatter={(value: number) => [formatCurrency(value), 'Amount']}
          />
          <Bar
            dataKey="value"
            radius={[0, 4, 4, 0]}
            barSize={24}
          >
            {data.map((entry, index) => (
              <Cell 
                key={`cell-${index}`} 
                fill={entry.fill}
                style={{
                  filter: 'url(#gritty)',
                }}
              />
            ))}
          </Bar>
          <defs>
            <filter id="gritty">
              <feTurbulence type="fractalNoise" baseFrequency="0.8" numOctaves="2" result="noise" />
              <feBlend in="SourceGraphic" in2="noise" mode="multiply" />
            </filter>
          </defs>
        </BarChart>
      </ResponsiveContainer>

      {/* Legend */}
      <div className="grid grid-cols-2 gap-4 mt-6">
        {data.map((item, index) => (
          <div key={item.name} className="flex items-center gap-2">
            <div
              className="w-3 h-3 rounded-sm"
              style={{ backgroundColor: item.fill }}
            />
            <span className="text-sm text-muted-foreground">{item.name}</span>
            <span className="ml-auto text-sm font-medium">
              {formatCurrency(item.value)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
