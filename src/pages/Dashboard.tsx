import { useEffect, useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import { 
  Plus, 
  LogOut, 
  FolderKanban, 
  TrendingUp, 
  TrendingDown,
  HardHat,
  Building2,
  Settings,
  Pencil,
  Trash2,
  MoreVertical,
  Package,
  BarChart3,
} from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
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
import EditProjectDialog from '@/components/EditProjectDialog';
import type { Tables } from '@/integrations/supabase/types';

type Project = Tables<'projects'>;

interface ProjectWithStats extends Project {
  totalIncome: number;
  totalCosts: number;
  netProfit: number;
}

export default function Dashboard() {
  const { user, loading: authLoading, signOut } = useAuth();
  const navigate = useNavigate();
  const [projects, setProjects] = useState<ProjectWithStats[]>([]);
  const [loading, setLoading] = useState(true);
  const [companyName, setCompanyName] = useState('');
  const [editingProject, setEditingProject] = useState<Project | null>(null);
  const [projectToDelete, setProjectToDelete] = useState<Project | null>(null);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    if (!authLoading && !user) {
      navigate('/auth');
    }
  }, [user, authLoading, navigate]);

  useEffect(() => {
    if (user) {
      fetchProjectsWithStats();
      fetchCompanyName();
    }
  }, [user]);

  const fetchCompanyName = async () => {
    const { data } = await supabase
      .from('profiles')
      .select('companies(name)')
      .eq('user_id', user!.id)
      .single();
    
    if (data?.companies) {
      setCompanyName((data.companies as { name: string }).name);
    }
  };

  const fetchProjectsWithStats = async () => {
    try {
      const { data: projectsData, error: projectsError } = await supabase
        .from('projects')
        .select('*')
        .order('created_at', { ascending: false });

      if (projectsError) throw projectsError;

      // Fetch income and costs for all projects
      const projectsWithStats = await Promise.all(
        (projectsData || []).map(async (project) => {
          const [incomeResult, costsResult] = await Promise.all([
            supabase
              .from('income')
              .select('amount')
              .eq('project_id', project.id),
            supabase
              .from('costs')
              .select('amount')
              .eq('project_id', project.id),
          ]);

          const totalIncome = (incomeResult.data || []).reduce(
            (sum, i) => sum + Number(i.amount),
            0
          );
          const totalCosts = (costsResult.data || []).reduce(
            (sum, c) => sum + Number(c.amount),
            0
          );

          return {
            ...project,
            totalIncome,
            totalCosts,
            netProfit: totalIncome - totalCosts,
          };
        })
      );

      setProjects(projectsWithStats);
    } catch (error) {
      toast.error('Failed to load projects');
    } finally {
      setLoading(false);
    }
  };

  const handleDeleteProject = async () => {
    if (!projectToDelete) return;

    setDeleting(true);
    try {
      const { error } = await supabase
        .from('projects')
        .delete()
        .eq('id', projectToDelete.id);

      if (error) throw error;

      toast.success('Project deleted successfully');
      fetchProjectsWithStats();
    } catch (error) {
      toast.error('Failed to delete project');
    } finally {
      setDeleting(false);
      setProjectToDelete(null);
    }
  };

  const handleSignOut = async () => {
    await signOut();
    navigate('/auth');
  };

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-KE', {
      style: 'currency',
      currency: 'KES',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    }).format(amount);
  };

  const getStatusClasses = (status: string) => {
    switch (status) {
      case 'active':
        return 'status-active';
      case 'completed':
        return 'status-completed';
      case 'on_hold':
        return 'status-on-hold';
      default:
        return '';
    }
  };

  if (authLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="animate-pulse text-primary">
          <HardHat className="w-12 h-12" />
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen">
      {/* Header */}
      <header className="border-b border-border bg-card/50 backdrop-blur-sm sticky top-0 z-40">
        <div className="container mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-primary/10 border border-primary/30 flex items-center justify-center">
              <HardHat className="w-5 h-5 text-primary" />
            </div>
            <div>
              <h1 className="font-heading text-lg tracking-tight">
                CONSTRUCT<span className="text-primary">LEDGER</span>
              </h1>
              {companyName && (
                <p className="text-xs text-muted-foreground flex items-center gap-1">
                  <Building2 className="w-3 h-3" />
                  {companyName}
                </p>
              )}
            </div>
          </div>

          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="sm"
              asChild
              className="text-muted-foreground hover:text-foreground"
            >
              <Link to="/reports">
                <BarChart3 className="w-4 h-4 mr-2" />
                Reports
              </Link>
            </Button>
            <Button
              variant="ghost"
              size="sm"
              asChild
              className="text-muted-foreground hover:text-foreground"
            >
              <Link to="/materials">
                <Package className="w-4 h-4 mr-2" />
                Materials
              </Link>
            </Button>
            <Button
              variant="ghost"
              size="sm"
              asChild
              className="text-muted-foreground hover:text-foreground"
            >
              <Link to="/settings">
                <Settings className="w-4 h-4 mr-2" />
                Settings
              </Link>
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={handleSignOut}
              className="text-muted-foreground hover:text-foreground"
            >
              <LogOut className="w-4 h-4 mr-2" />
              Sign Out
            </Button>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-4 py-8">
        {/* Page Title */}
        <div className="flex items-center justify-between mb-8 stagger-fade-in" style={{ animationDelay: '0ms' }}>
          <div>
            <h2 className="text-2xl font-heading">PROJECTS</h2>
            <p className="text-muted-foreground">
              Track profitability across all your construction projects
            </p>
          </div>
          <Button asChild className="tactile-press">
            <Link to="/projects/new">
              <Plus className="w-4 h-4 mr-2" />
              New Project
            </Link>
          </Button>
        </div>

        {/* Projects Grid */}
        {loading ? (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {[1, 2, 3].map((i) => (
              <div key={i} className="industrial-card p-6">
                <Skeleton className="h-6 w-3/4 mb-4" />
                <Skeleton className="h-4 w-1/2 mb-6" />
                <Skeleton className="h-10 w-full" />
              </div>
            ))}
          </div>
        ) : projects.length === 0 ? (
          <div 
            className="industrial-card p-12 text-center stagger-fade-in" 
            style={{ animationDelay: '100ms' }}
          >
            <FolderKanban className="w-12 h-12 text-muted-foreground mx-auto mb-4" />
            <h3 className="font-heading text-xl mb-2">NO PROJECTS YET</h3>
            <p className="text-muted-foreground mb-6">
              Create your first project to start tracking costs and income
            </p>
            <Button asChild className="tactile-press">
              <Link to="/projects/new">
                <Plus className="w-4 h-4 mr-2" />
                Create First Project
              </Link>
            </Button>
          </div>
        ) : (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {projects.map((project, index) => (
              <div
                key={project.id}
                className="industrial-card p-6 hover:border-primary/50 transition-colors group stagger-fade-in relative"
                style={{ animationDelay: `${index * 50}ms` }}
              >
                {/* Actions dropdown */}
                <div className="absolute top-4 right-4 opacity-0 group-hover:opacity-100 transition-opacity">
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8"
                        onClick={(e) => e.preventDefault()}
                      >
                        <MoreVertical className="w-4 h-4" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem
                        onClick={(e) => {
                          e.preventDefault();
                          setEditingProject(project);
                        }}
                      >
                        <Pencil className="w-4 h-4 mr-2" />
                        Edit
                      </DropdownMenuItem>
                      <DropdownMenuItem
                        onClick={(e) => {
                          e.preventDefault();
                          setProjectToDelete(project);
                        }}
                        className="text-destructive focus:text-destructive"
                      >
                        <Trash2 className="w-4 h-4 mr-2" />
                        Delete
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>

                <Link to={`/projects/${project.id}`} className="block">
                  <div className="flex items-start justify-between mb-4 pr-8">
                    <div className="flex-1 min-w-0">
                      <h3 className="font-heading text-lg truncate group-hover:text-primary transition-colors">
                        {project.name}
                      </h3>
                      {project.client_name && (
                        <p className="text-sm text-muted-foreground truncate">
                          {project.client_name}
                        </p>
                      )}
                    </div>
                    <span className={`text-xs px-2 py-1 rounded border ${getStatusClasses(project.status)}`}>
                      {project.status.replace('_', ' ')}
                    </span>
                  </div>

                  {/* P&L Summary */}
                  <div className="space-y-2 pt-4 border-t border-border">
                    <div className="flex justify-between text-sm">
                      <span className="text-muted-foreground">Income</span>
                      <span className="text-success">{formatCurrency(project.totalIncome)}</span>
                    </div>
                    <div className="flex justify-between text-sm">
                      <span className="text-muted-foreground">Costs</span>
                      <span className="text-destructive">{formatCurrency(project.totalCosts)}</span>
                    </div>
                    <div className="flex justify-between items-center pt-2 border-t border-border">
                      <span className="font-semibold">Net Profit</span>
                      <span
                        className={`text-lg font-heading flex items-center gap-1 ${
                          project.netProfit >= 0 
                            ? 'text-success profit-glow' 
                            : 'text-destructive loss-glow'
                        }`}
                      >
                        {project.netProfit >= 0 ? (
                          <TrendingUp className="w-4 h-4" />
                        ) : (
                          <TrendingDown className="w-4 h-4" />
                        )}
                        {formatCurrency(project.netProfit)}
                      </span>
                    </div>
                  </div>
                </Link>
              </div>
            ))}
          </div>
        )}
      </main>

      {/* Edit Project Dialog */}
      <EditProjectDialog
        open={!!editingProject}
        onOpenChange={(open) => !open && setEditingProject(null)}
        project={editingProject}
        onSuccess={fetchProjectsWithStats}
      />

      {/* Delete Project Dialog */}
      <AlertDialog open={!!projectToDelete} onOpenChange={() => setProjectToDelete(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete Project?</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently delete "{projectToDelete?.name}" and all its costs and income records. This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDeleteProject}
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
