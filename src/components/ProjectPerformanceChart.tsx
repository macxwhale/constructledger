import { BarChart, Bar, XAxis, YAxis, ResponsiveContainer, Tooltip, Legend, CartesianGrid } from 'recharts';

interface ProjectData {
  name: string;
  totalIncome: number;
  totalCosts: number;
}

interface ProjectPerformanceChartProps {
  data: ProjectData[];
}

export default function ProjectPerformanceChart({ data }: ProjectPerformanceChartProps) {
  const formatCurrency = (value: number) => {
    return new Intl.NumberFormat('en-KE', {
      style: 'currency',
      currency: 'KES',
      notation: 'compact',
      compactDisplay: 'short',
    }).format(value);
  };

  const formatTooltipCurrency = (value: number) => {
    return new Intl.NumberFormat('en-KE', {
      style: 'currency',
      currency: 'KES',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    }).format(value);
  };

  if (data.length === 0) {
    return (
      <div className="h-80 flex items-center justify-center text-muted-foreground">
        No projects to display
      </div>
    );
  }

  return (
    <div className="h-80 w-full mt-4">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart
          data={data}
          margin={{ top: 20, right: 0, left: 0, bottom: 20 }}
          barGap={4}
        >
          <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="hsl(220, 13%, 20%)" />
          <XAxis 
            dataKey="name" 
            axisLine={true}
            tickLine={false}
            tick={{ fill: 'hsl(215, 20%, 55%)', fontSize: 12 }}
            dy={10}
            // Truncate long names slightly for XAxis
            tickFormatter={(value) => value.length > 15 ? value.substring(0, 15) + '...' : value}
          />
          <YAxis 
            tickFormatter={formatCurrency}
            axisLine={false}
            tickLine={false}
            tick={{ fill: 'hsl(215, 20%, 55%)', fontSize: 12 }}
            width={60}
          />
          <Tooltip 
            cursor={{ fill: 'hsl(220, 14%, 16%)' }}
            contentStyle={{
              backgroundColor: 'hsl(220, 18%, 11%)',
              border: '1px solid hsl(220, 13%, 20%)',
              borderRadius: '8px',
              boxShadow: '0 4px 20px -4px rgba(0,0,0,0.5)',
            }}
            labelStyle={{ color: 'hsl(214, 32%, 91%)', fontWeight: 600, marginBottom: '8px' }}
            formatter={(value: number, name: string) => [
              formatTooltipCurrency(value), 
              name === 'totalIncome' ? 'Total Income' : 'Total Costs'
            ]}
          />
          <Legend 
            wrapperStyle={{ paddingTop: '20px' }}
            formatter={(value) => <span className="text-muted-foreground text-sm">{value === 'totalIncome' ? 'Income' : 'Costs'}</span>}
          />
          
          <Bar 
            dataKey="totalIncome" 
            fill="hsl(160, 84%, 39%)" 
            radius={[4, 4, 0, 0]}
            maxBarSize={50}
          />
          <Bar 
            dataKey="totalCosts" 
            fill="hsl(0, 84%, 60%)" 
            radius={[4, 4, 0, 0]} 
            maxBarSize={50}
          />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
