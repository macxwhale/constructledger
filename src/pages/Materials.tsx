import { useEffect, useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import {
  ArrowLeft,
  Package,
  HardHat,
  Plus,
  Loader2,
  Trash2,
} from 'lucide-react';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
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

interface Material {
  id: string;
  name: string;
  unit: string | null;
  default_unit_cost: number | null;
}

export default function Materials() {
  const { user, loading: authLoading } = useAuth();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [materials, setMaterials] = useState<Material[]>([]);
  const [isManager, setIsManager] = useState(false);
  const [companyId, setCompanyId] = useState<string | null>(null);

  // Add material form state
  const [name, setName] = useState('');
  const [unit, setUnit] = useState('');
  const [defaultCost, setDefaultCost] = useState('');
  const [adding, setAdding] = useState(false);

  // Delete state
  const [materialToDelete, setMaterialToDelete] = useState<Material | null>(null);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    if (!authLoading && !user) {
      navigate('/auth');
    }
  }, [user, authLoading, navigate]);

  useEffect(() => {
    if (user) {
      fetchUserContext();
    }
  }, [user]);

  const fetchUserContext = async () => {
    try {
      const { data: profile } = await supabase
        .from('profiles')
        .select('company_id')
        .eq('user_id', user!.id)
        .single();

      if (profile?.company_id) {
        setCompanyId(profile.company_id);
        
        const { data: roleData } = await supabase
          .from('user_roles')
          .select('role')
          .eq('user_id', user!.id)
          .eq('company_id', profile.company_id)
          .single();
          
        setIsManager(roleData?.role === 'manager');
        fetchMaterials(profile.company_id);
      } else {
        setLoading(false);
      }
    } catch (error) {
      toast.error('Failed to load user context');
      setLoading(false);
    }
  };

  const fetchMaterials = async (compId: string) => {
    try {
      const { data, error } = await supabase
        .from('materials')
        .select('id, name, unit, default_unit_cost')
        .eq('company_id', compId)
        .order('name', { ascending: true });

      if (error) throw error;
      setMaterials(data || []);
    } catch (error) {
      console.error('Fetch materials error:', error);
      toast.error('Failed to load materials. Please ensure database migrations are run.');
    } finally {
      setLoading(false);
    }
  };

  const handleAddMaterial = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim() || !companyId) return;

    setAdding(true);
    try {
      const { data, error } = await supabase
        .from('materials')
        .insert({
          company_id: companyId,
          name: name.trim(),
          unit: unit.trim() || null,
          default_unit_cost: defaultCost ? parseFloat(defaultCost) : null,
        })
        .select('id, name, unit, default_unit_cost')
        .single();

      if (error) throw error;

      toast.success('Material added successfully');
      setMaterials([...materials, data].sort((a, b) => a.name.localeCompare(b.name)));
      setName('');
      setUnit('');
      setDefaultCost('');
    } catch (error) {
      toast.error('Failed to add material');
    } finally {
      setAdding(false);
    }
  };

  const handleDeleteMaterial = async () => {
    if (!materialToDelete) return;

    setDeleting(true);
    try {
      const { error } = await supabase
        .from('materials')
        .delete()
        .eq('id', materialToDelete.id);

      if (error) throw error;

      toast.success('Material deleted');
      setMaterials(materials.filter((m) => m.id !== materialToDelete.id));
    } catch (error) {
      toast.error('Failed to delete material');
    } finally {
      setDeleting(false);
      setMaterialToDelete(null);
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
      <main className="container mx-auto px-4 py-8 max-w-4xl">
        <div className="mb-8 stagger-fade-in" style={{ animationDelay: '0ms' }}>
          <h1 className="text-3xl font-heading mb-2 flex items-center gap-3">
            <Package className="w-8 h-8 text-primary" />
            MATERIALS CATALOGUE
          </h1>
          <p className="text-muted-foreground">
            Manage standard materials and base costs for your projects
          </p>
        </div>

        <div className="grid md:grid-cols-3 gap-8">
          {/* Add Material Form (Managers Only) */}
          <div className="md:col-span-1 stagger-fade-in" style={{ animationDelay: '100ms' }}>
            {isManager ? (
              <Card className="industrial-card sticky top-24">
                <CardHeader>
                  <CardTitle className="font-heading text-lg">ADD MATERIAL</CardTitle>
                </CardHeader>
                <CardContent>
                  <form onSubmit={handleAddMaterial} className="space-y-4">
                    <div className="space-y-2">
                      <Label htmlFor="name">Name *</Label>
                      <Input
                        id="name"
                        placeholder="e.g. Portland Cement"
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        disabled={adding}
                        required
                        className="bg-input border-border"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="unit">Unit</Label>
                      <Input
                        id="unit"
                        placeholder="e.g. 50kg bag, pieces"
                        value={unit}
                        onChange={(e) => setUnit(e.target.value)}
                        disabled={adding}
                        className="bg-input border-border"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="defaultCost">Base Cost (KSH)</Label>
                      <Input
                        id="defaultCost"
                        type="number"
                        step="0.01"
                        placeholder="e.g. 800"
                        value={defaultCost}
                        onChange={(e) => setDefaultCost(e.target.value)}
                        disabled={adding}
                        className="bg-input border-border"
                      />
                      <p className="text-xs text-muted-foreground">
                        This cost will auto-fill when logging project expenses, but can be overridden.
                      </p>
                    </div>
                    <Button type="submit" disabled={adding || !name.trim()} className="w-full tactile-press">
                      {adding ? (
                        <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                      ) : (
                        <Plus className="w-4 h-4 mr-2" />
                      )}
                      Add to Catalogue
                    </Button>
                  </form>
                </CardContent>
              </Card>
            ) : (
              <div className="industrial-card p-6 bg-secondary/20">
                <p className="text-sm text-muted-foreground">
                  Only managers can add or remove materials from the catalogue.
                </p>
              </div>
            )}
          </div>

          {/* Materials List */}
          <div className="md:col-span-2 stagger-fade-in" style={{ animationDelay: '200ms' }}>
            <Card className="industrial-card">
              <CardHeader>
                <CardTitle className="font-heading text-lg">AVAILABLE MATERIALS</CardTitle>
                <CardDescription>
                  {materials.length} item{materials.length !== 1 && 's'} in catalogue
                </CardDescription>
              </CardHeader>
              <CardContent>
                {materials.length === 0 ? (
                  <div className="text-center py-12">
                    <Package className="w-12 h-12 text-muted-foreground/50 mx-auto mb-4" />
                    <p className="text-muted-foreground">No materials added yet.</p>
                  </div>
                ) : (
                  <div className="space-y-3">
                    {materials.map((material) => (
                      <div
                        key={material.id}
                        className="flex items-center justify-between p-4 bg-secondary/30 rounded-lg hover:border-primary/30 border border-transparent transition-colors group"
                      >
                        <div className="flex-1 min-w-0 pr-4">
                          <h4 className="font-medium truncate">{material.name}</h4>
                          <div className="flex gap-4 mt-1 text-sm text-muted-foreground">
                            {material.unit && (
                              <span>Unit: {material.unit}</span>
                            )}
                            {material.default_unit_cost !== null && (
                              <span className="text-foreground">
                                Base Rate: {formatCurrency(material.default_unit_cost)}
                              </span>
                            )}
                          </div>
                        </div>
                        {isManager && (
                          <Button
                            variant="ghost"
                            size="icon"
                            className="text-muted-foreground hover:text-destructive opacity-0 group-hover:opacity-100 transition-opacity"
                            onClick={() => setMaterialToDelete(material)}
                          >
                            <Trash2 className="w-4 h-4" />
                          </Button>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </div>
      </main>

      {/* Delete Confirmation */}
      <AlertDialog open={!!materialToDelete} onOpenChange={() => setMaterialToDelete(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete Material?</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to remove "{materialToDelete?.name}" from your catalogue? 
              This won't affect past logged costs.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDeleteMaterial}
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
