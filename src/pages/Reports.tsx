import { useEffect, useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import {
  ArrowLeft,
  HardHat,
  BarChart3,
  TrendingUp,
  TrendingDown,
} from 'lucide-react';
import CostBreakdownChart from '@/components/CostBreakdownChart';
import ProjectPerformanceChart from '@/components/ProjectPerformanceChart';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';

interface ReportsData {
  totalIncome: number;
  totalCosts: number;
  netProfit: number;
  costsByType: {
    materials: number;
    labor: number;
    equipment: number;
    subcontractors: number;
  };
  projectPerformance: {
    name: string;
    totalIncome: number;
    totalCosts: number;
  }[];
}

export default function Reports() {
  const { user, loading: authLoading } = useAuth();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [reportData, setReportData] = useState<ReportsData | null>(null);

  useEffect(() => {
    if (!authLoading && !user) {
      navigate('/auth');
    }
  }, [user, authLoading, navigate]);

  useEffect(() => {
    if (user) {
      fetchAggregatedData();
    }
  }, [user]);

  const fetchAggregatedData = async () => {
    try {
      // Due to Row Level Security, querying these tables naturally returns 
      // ONLY the records associated with the user's company.
      const [projectsResult, costsResult, incomeResult] = await Promise.all([
        supabase.from('projects').select('id, name'),
        supabase.from('costs').select('amount, cost_type, project_id'),
        supabase.from('income').select('amount, project_id')
      ]);

      if (projectsResult.error) throw projectsResult.error;
      if (costsResult.error) throw costsResult.error;
      if (incomeResult.error) throw incomeResult.error;

      const projects = projectsResult.data || [];
      const costs = costsResult.data || [];
      const income = incomeResult.data || [];

      // Global aggregations
      const totalIncome = income.reduce((sum, i) => sum + Number(i.amount), 0);
      const totalCosts = costs.reduce((sum, c) => sum + Number(c.amount), 0);
      
      const costsByType = {
        materials: costs.filter(c => c.cost_type === 'materials').reduce((sum, c) => sum + Number(c.amount), 0),
        labor: costs.filter(c => c.cost_type === 'labor').reduce((sum, c) => sum + Number(c.amount), 0),
        equipment: costs.filter(c => c.cost_type === 'equipment').reduce((sum, c) => sum + Number(c.amount), 0),
        subcontractors: costs.filter(c => c.cost_type === 'subcontractors').reduce((sum, c) => sum + Number(c.amount), 0),
      };

      // Per-project performance mapping
      const projectPerformance = projects.map(p => {
        const pIncome = income.filter(i => i.project_id === p.id).reduce((sum, i) => sum + Number(i.amount), 0);
        const pCosts = costs.filter(c => c.project_id === p.id).reduce((sum, c) => sum + Number(c.amount), 0);
        return {
          name: p.name,
          totalIncome: pIncome,
          totalCosts: pCosts,
          // Used just for sorting
          netProfit: pIncome - pCosts
        };
      })
      .sort((a, b) => b.netProfit - a.netProfit) // Top profitable first
      .map(({ netProfit, ...rest }) => rest);

      setReportData({
        totalIncome,
        totalCosts,
        netProfit: totalIncome - totalCosts,
        costsByType,
        projectPerformance
      });

    } catch (error) {
      console.error('Failed to load reports:', error);
      toast.error('Failed to load report data');
    } finally {
      setLoading(false);
    }
  };

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-KE', {
      style: 'currency',
      currency: 'KES',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    }).format(amount);
  };

  if (authLoading || loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="animate-pulse text-primary">
          <HardHat className="w-12 h-12" />
        </div>
      </div>
    );
  }

  if (!reportData) return null;

  return (
    <div className="min-h-screen">
      {/* Header */}
      <header className="border-b border-border bg-card/50 backdrop-blur-sm sticky top-0 z-40">
        <div className="container mx-auto px-4 py-4">
          <Button
            variant="ghost"
            size="sm"
            asChild
            className="text-muted-foreground hover:text-foreground"
          >
            <Link to="/dashboard">
              <ArrowLeft className="w-4 h-4 mr-2" />
              Back to Dashboard
            </Link>
          </Button>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-4 py-8">
        <div className="mb-8 stagger-fade-in" style={{ animationDelay: '0ms' }}>
          <h1 className="text-3xl font-heading mb-2 flex items-center gap-3">
            <BarChart3 className="w-8 h-8 text-primary" />
            FINANCIAL REPORTS
          </h1>
          <p className="text-muted-foreground">
            Multi-project aggregate data and company performance
          </p>
        </div>

        {/* Global KPIs Hero */}
        <div className="industrial-card p-8 mb-8 stagger-fade-in" style={{ animationDelay: '50ms' }}>
          <div className="grid md:grid-cols-3 gap-8">
            <div className="text-center">
              <p className="text-muted-foreground text-sm uppercase tracking-wider mb-2">Global Income</p>
              <p className="text-3xl font-heading text-success">{formatCurrency(reportData.totalIncome)}</p>
            </div>

            <div className="text-center">
              <p className="text-muted-foreground text-sm uppercase tracking-wider mb-2">Global Costs</p>
              <p className="text-3xl font-heading text-destructive">{formatCurrency(reportData.totalCosts)}</p>
            </div>

            <div className="text-center">
              <p className="text-muted-foreground text-sm uppercase tracking-wider mb-2">Company Profit</p>
              <div className="flex items-center justify-center gap-2">
                {reportData.netProfit >= 0 ? (
                  <TrendingUp className="w-8 h-8 text-success" />
                ) : (
                  <TrendingDown className="w-8 h-8 text-destructive" />
                )}
                <p
                  className={`text-4xl font-heading ${
                    reportData.netProfit >= 0 ? 'text-success profit-glow' : 'text-destructive loss-glow'
                  }`}
                >
                  {formatCurrency(reportData.netProfit)}
                </p>
              </div>
            </div>
          </div>
        </div>

        <div className="grid lg:grid-cols-2 gap-8 stagger-fade-in" style={{ animationDelay: '100ms' }}>
          {/* Project Performance Chart */}
          <Card className="industrial-card">
            <CardHeader>
              <CardTitle className="font-heading text-lg">PROJECT PERFORMANCE</CardTitle>
              <CardDescription>Income vs Costs sorted by profitability</CardDescription>
            </CardHeader>
            <CardContent>
              <ProjectPerformanceChart data={reportData.projectPerformance} />
            </CardContent>
          </Card>

          {/* Global Cost Breakdown Chart */}
          <Card className="industrial-card">
            <CardHeader>
              <CardTitle className="font-heading text-lg">GLOBAL COST DISTRIBUTION</CardTitle>
              <CardDescription>Aggregate category breakdown across all projects</CardDescription>
            </CardHeader>
            <CardContent>
              <CostBreakdownChart costsByType={reportData.costsByType} />
            </CardContent>
          </Card>
        </div>
      </main>
    </div>
  );
}
