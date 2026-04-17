import { useEffect, useState } from 'react';
import { useNavigate, useParams, Link } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import {
  ArrowLeft,
  HardHat,
  TrendingUp,
  TrendingDown,
  DollarSign,
  Package,
  Users,
  Truck,
  Hammer,
  Plus,
  Pencil,
  Trash2,
} from 'lucide-react';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import type { Tables } from '@/integrations/supabase/types';
import AddCostSheet from '@/components/AddCostSheet';
import AddIncomeSheet from '@/components/AddIncomeSheet';
import CostBreakdownChart from '@/components/CostBreakdownChart';

type Project = Tables<'projects'>;
type Cost = Tables<'costs'>;
type Income = Tables<'income'>;

export default function ProjectPage() {
  const { id } = useParams<{ id: string }>();
  const { user, loading: authLoading } = useAuth();
  const navigate = useNavigate();
  const [project, setProject] = useState<Project | null>(null);
  const [costs, setCosts] = useState<Cost[]>([]);
  const [income, setIncome] = useState<Income[]>([]);
  const [loading, setLoading] = useState(true);
  const [addCostOpen, setAddCostOpen] = useState(false);
  const [addIncomeOpen, setAddIncomeOpen] = useState(false);
  const [selectedCostType, setSelectedCostType] = useState<string | null>(null);
  const [editingCost, setEditingCost] = useState<Cost | null>(null);
  const [editingIncome, setEditingIncome] = useState<Income | null>(null);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [itemToDelete, setItemToDelete] = useState<{ type: 'cost' | 'income'; id: string } | null>(null);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    if (!authLoading && !user) {
      navigate('/auth');
    }
  }, [user, authLoading, navigate]);

  useEffect(() => {
    if (user && id) {
      fetchProjectData();
    }
  }, [user, id]);

  const fetchProjectData = async () => {
    try {
      const [projectResult, costsResult, incomeResult] = await Promise.all([
        supabase.from('projects').select('*').eq('id', id).single(),
        supabase.from('costs').select('*').eq('project_id', id).order('date', { ascending: false }),
        supabase.from('income').select('*').eq('project_id', id).order('date', { ascending: false }),
      ]);

      if (projectResult.error) throw projectResult.error;
      
      setProject(projectResult.data);
      setCosts(costsResult.data || []);
      setIncome(incomeResult.data || []);
    } catch (error) {
      toast.error('Failed to load project');
      navigate('/dashboard');
    } finally {
      setLoading(false);
    }
  };

  const totalIncome = income.reduce((sum, i) => sum + Number(i.amount), 0);
  const totalCosts = costs.reduce((sum, c) => sum + Number(c.amount), 0);
  const netProfit = totalIncome - totalCosts;

  const costsByType = {
    materials: costs.filter((c) => c.cost_type === 'materials').reduce((sum, c) => sum + (Number(c.amount) - Number(c.labor_cost || 0) - Number(c.transport_cost || 0)), 0),
    labor: costs.filter((c) => c.cost_type === 'labor').reduce((sum, c) => sum + Number(c.amount), 0) + 
           costs.filter((c) => c.cost_type === 'materials').reduce((sum, c) => sum + Number(c.labor_cost || 0), 0),
    equipment: costs.filter((c) => c.cost_type === 'equipment').reduce((sum, c) => sum + Number(c.amount), 0),
    subcontractors: costs.filter((c) => c.cost_type === 'subcontractors').reduce((sum, c) => sum + Number(c.amount), 0),
    transport: costs.reduce((sum, c) => sum + Number(c.transport_cost || 0), 0),
  };

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-KE', {
      style: 'currency',
      currency: 'KES',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    }).format(amount);
  };

  const handleOpenAddCost = (type: string) => {
    setSelectedCostType(type);
    setEditingCost(null);
    setAddCostOpen(true);
  };

  const handleEditCost = (cost: Cost) => {
    setEditingCost(cost);
    setSelectedCostType(cost.cost_type);
    setAddCostOpen(true);
  };

  const handleEditIncome = (incomeItem: Income) => {
    setEditingIncome(incomeItem);
    setAddIncomeOpen(true);
  };

  const handleOpenAddIncome = () => {
    setEditingIncome(null);
    setAddIncomeOpen(true);
  };

  const handleDeleteClick = (type: 'cost' | 'income', itemId: string) => {
    setItemToDelete({ type, id: itemId });
    setDeleteDialogOpen(true);
  };

  const handleConfirmDelete = async () => {
    if (!itemToDelete) return;

    setDeleting(true);
    try {
      const { error } = await supabase
        .from(itemToDelete.type === 'cost' ? 'costs' : 'income')
        .delete()
        .eq('id', itemToDelete.id);

      if (error) throw error;

      toast.success(`${itemToDelete.type === 'cost' ? 'Cost' : 'Income'} deleted successfully`);
      fetchProjectData();
    } catch (error) {
      toast.error('Failed to delete item');
    } finally {
      setDeleting(false);
      setDeleteDialogOpen(false);
      setItemToDelete(null);
    }
  };

  const getCostTypeIcon = (costType: string) => {
    switch (costType) {
      case 'materials': return <Package className="w-5 h-5 text-chart-1" />;
      case 'labor': return <Users className="w-5 h-5 text-chart-2" />;
      case 'equipment': return <Truck className="w-5 h-5 text-chart-3" />;
      case 'subcontractors': return <Hammer className="w-5 h-5 text-chart-4" />;
      default: return <Package className="w-5 h-5 text-destructive" />;
    }
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

  if (!project) return null;

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
        {/* Project Header */}
        <div className="mb-8 stagger-fade-in" style={{ animationDelay: '0ms' }}>
          <h1 className="text-3xl font-heading mb-2">{project.name}</h1>
          {project.client_name && (
            <p className="text-muted-foreground">{project.client_name}</p>
          )}
        </div>

        {/* P&L Hero */}
        <div className="industrial-card p-8 mb-8 stagger-fade-in" style={{ animationDelay: '50ms' }}>
          <div className="grid md:grid-cols-3 gap-8">
            {/* Total Income */}
            <div className="text-center">
              <p className="text-muted-foreground text-sm uppercase tracking-wider mb-2">Total Income</p>
              <p className="text-3xl font-heading text-success">{formatCurrency(totalIncome)}</p>
            </div>

            {/* Total Costs */}
            <div className="text-center">
              <p className="text-muted-foreground text-sm uppercase tracking-wider mb-2">Total Costs</p>
              <p className="text-3xl font-heading text-destructive">{formatCurrency(totalCosts)}</p>
            </div>

            {/* Net Profit */}
            <div className="text-center">
              <p className="text-muted-foreground text-sm uppercase tracking-wider mb-2">Net Profit</p>
              <div className="flex items-center justify-center gap-2">
                {netProfit >= 0 ? (
                  <TrendingUp className="w-8 h-8 text-success" />
                ) : (
                  <TrendingDown className="w-8 h-8 text-destructive" />
                )}
                <p
                  className={`text-4xl font-heading ${
                    netProfit >= 0 ? 'text-success profit-glow' : 'text-destructive loss-glow'
                  }`}
                >
                  {formatCurrency(netProfit)}
                </p>
              </div>
            </div>
          </div>
        </div>

        <div className="grid lg:grid-cols-3 gap-8">
          {/* Cost Breakdown Chart */}
          <div className="lg:col-span-2 stagger-fade-in" style={{ animationDelay: '100ms' }}>
            <div className="industrial-card p-6">
              <h2 className="font-heading text-lg mb-6">COST BREAKDOWN</h2>
              <CostBreakdownChart costsByType={costsByType} />
            </div>
          </div>

          {/* Quick Actions */}
          <div className="stagger-fade-in" style={{ animationDelay: '150ms' }}>
            <div className="industrial-card p-6">
              <h2 className="font-heading text-lg mb-6">QUICK ADD</h2>
              
              {/* Add Income */}
              <Button
                variant="outline"
                className="w-full mb-4 justify-start tactile-press border-success/30 hover:bg-success/10 hover:border-success/50"
                onClick={handleOpenAddIncome}
              >
                <DollarSign className="w-4 h-4 mr-3 text-success" />
                Add Income
              </Button>

              {/* Cost Types */}
              <div className="space-y-2">
                <Button
                  variant="outline"
                  className="w-full justify-start tactile-press"
                  onClick={() => handleOpenAddCost('materials')}
                >
                  <Package className="w-4 h-4 mr-3 text-chart-1" />
                  Materials
                  <span className="ml-auto text-muted-foreground text-sm">
                    {formatCurrency(costsByType.materials)}
                  </span>
                </Button>

                <Button
                  variant="outline"
                  className="w-full justify-start tactile-press"
                  onClick={() => handleOpenAddCost('labor')}
                >
                  <Users className="w-4 h-4 mr-3 text-chart-2" />
                  Labor
                  <span className="ml-auto text-muted-foreground text-sm">
                    {formatCurrency(costsByType.labor)}
                  </span>
                </Button>

                <Button
                  variant="outline"
                  className="w-full justify-start tactile-press"
                  onClick={() => handleOpenAddCost('equipment')}
                >
                  <Truck className="w-4 h-4 mr-3 text-chart-3" />
                  Equipment
                  <span className="ml-auto text-muted-foreground text-sm">
                    {formatCurrency(costsByType.equipment)}
                  </span>
                </Button>

                <Button
                  variant="outline"
                  className="w-full justify-start tactile-press"
                  onClick={() => handleOpenAddCost('subcontractors')}
                >
                  <Hammer className="w-4 h-4 mr-3 text-chart-4" />
                  Subcontractors
                  <span className="ml-auto text-muted-foreground text-sm">
                    {formatCurrency(costsByType.subcontractors)}
                  </span>
                </Button>

                <div className="flex items-center p-3 rounded-md border border-border bg-secondary/10">
                  <Truck className="w-4 h-4 mr-3 text-chart-5" style={{ color: 'hsl(330, 80%, 60%)' }} />
                  <span className="text-sm">Transport</span>
                  <span className="ml-auto text-muted-foreground text-sm font-medium">
                    {formatCurrency(costsByType.transport)}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Recent Transactions */}
        <div className="mt-8 stagger-fade-in" style={{ animationDelay: '200ms' }}>
          <div className="industrial-card p-6">
            <h2 className="font-heading text-lg mb-6">RECENT TRANSACTIONS</h2>
            
            {costs.length === 0 && income.length === 0 ? (
              <div className="text-center py-12">
                <p className="text-muted-foreground mb-4">No transactions yet</p>
                <Button onClick={() => setAddCostOpen(true)} className="tactile-press">
                  <Plus className="w-4 h-4 mr-2" />
                  Add First Transaction
                </Button>
              </div>
            ) : (
              <div className="space-y-2">
                {[...costs.map(c => ({ ...c, type: 'cost' as const })), 
                  ...income.map(i => ({ ...i, type: 'income' as const }))]
                  .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
                  .map((item, index) => (
                    <div
                      key={item.id}
                      className="flex items-center justify-between p-4 bg-secondary/30 rounded-lg slide-in-lock group"
                      style={{ animationDelay: `${index * 50}ms` }}
                    >
                      <div className="flex items-center gap-3 flex-1 min-w-0">
                        {item.type === 'income' ? (
                          <DollarSign className="w-5 h-5 text-success flex-shrink-0" />
                        ) : (
                          getCostTypeIcon((item as Cost).cost_type)
                        )}
                        <div className="min-w-0 flex-1">
                          <p className="font-medium truncate">{item.description || 'No description'}</p>
                          <p className="text-sm text-muted-foreground">
                            {new Date(item.date).toLocaleDateString()}
                            {item.type === 'cost' && ` • ${(item as Cost).cost_type}`}
                          </p>
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        <span
                          className={`font-heading ${
                            item.type === 'income' ? 'text-success' : 'text-destructive'
                          }`}
                        >
                          {item.type === 'income' ? '+' : '-'}{formatCurrency(Number(item.amount))}
                        </span>
                        <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-8 w-8"
                            onClick={() => item.type === 'cost' 
                              ? handleEditCost(item as Cost) 
                              : handleEditIncome(item as Income)
                            }
                          >
                            <Pencil className="w-4 h-4" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-8 w-8 text-destructive hover:text-destructive"
                            onClick={() => handleDeleteClick(item.type, item.id)}
                          >
                            <Trash2 className="w-4 h-4" />
                          </Button>
                        </div>
                      </div>
                    </div>
                  ))}
              </div>
            )}
          </div>
        </div>
      </main>

      {/* Sheets */}
      <AddCostSheet
        open={addCostOpen}
        onOpenChange={(open) => {
          setAddCostOpen(open);
          if (!open) setEditingCost(null);
        }}
        projectId={id!}
        defaultCostType={selectedCostType}
        editingCost={editingCost}
        onSuccess={fetchProjectData}
      />

      <AddIncomeSheet
        open={addIncomeOpen}
        onOpenChange={(open) => {
          setAddIncomeOpen(open);
          if (!open) setEditingIncome(null);
        }}
        projectId={id!}
        editingIncome={editingIncome}
        onSuccess={fetchProjectData}
      />

      {/* Delete Confirmation Dialog */}
      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete {itemToDelete?.type === 'cost' ? 'Cost' : 'Income'}?</AlertDialogTitle>
            <AlertDialogDescription>
              This action cannot be undone. This will permanently delete this {itemToDelete?.type === 'cost' ? 'cost entry' : 'income entry'} from the project.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleConfirmDelete}
              disabled={deleting}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {deleting ? 'Deleting...' : 'Delete'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
