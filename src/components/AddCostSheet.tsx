import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { toast } from 'sonner';
import { Loader2, Package, Users, Truck, Hammer } from 'lucide-react';

interface CostData {
  id: string;
  cost_type: 'materials' | 'labor' | 'equipment' | 'subcontractors';
  amount: number;
  description: string;
  date: string;
  supplier?: string | null;
  quantity?: number | null;
  unit_cost?: number | null;
  worker_name?: string | null;
  hours?: number | null;
  hourly_rate?: number | null;
  equipment_name?: string | null;
  rental_days?: number | null;
  daily_rate?: number | null;
  contractor_name?: string | null;
  invoice_reference?: string | null;
  labor_cost?: number | null;
  transport_cost?: number | null;
}

interface Material {
  id: string;
  name: string;
  default_unit_cost: number | null;
}

interface AddCostSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  projectId: string;
  defaultCostType?: string | null;
  editingCost?: CostData | null;
  onSuccess: () => void;
}

const costTypeIcons = {
  materials: Package,
  labor: Users,
  equipment: Truck,
  subcontractors: Hammer,
};

const costTypeLabels = {
  materials: 'Materials',
  labor: 'Labor',
  equipment: 'Equipment',
  subcontractors: 'Subcontractors',
};

export default function AddCostSheet({
  open,
  onOpenChange,
  projectId,
  defaultCostType,
  editingCost,
  onSuccess,
}: AddCostSheetProps) {
  const { user } = useAuth();
  const [loading, setLoading] = useState(false);
  const [costType, setCostType] = useState(defaultCostType || 'materials');
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [date, setDate] = useState(new Date().toISOString().split('T')[0]);
  const [materials, setMaterials] = useState<Material[]>([]);

  // Materials fields
  const [itemName, setItemName] = useState('');
  const [supplier, setSupplier] = useState('');
  const [quantity, setQuantity] = useState('');
  const [unitCost, setUnitCost] = useState('');
  const [materialLaborCost, setMaterialLaborCost] = useState('');
  const [transportCost, setTransportCost] = useState('');

  // Labor fields
  const [workerName, setWorkerName] = useState('');
  const [hours, setHours] = useState('');
  const [hourlyRate, setHourlyRate] = useState('');

  // Equipment fields
  const [equipmentName, setEquipmentName] = useState('');
  const [rentalDays, setRentalDays] = useState('');
  const [dailyRate, setDailyRate] = useState('');

  // Subcontractor fields
  const [contractorName, setContractorName] = useState('');
  const [invoiceReference, setInvoiceReference] = useState('');

  // Initialize form when editing
  useEffect(() => {
    if (editingCost) {
      setCostType(editingCost.cost_type);
      setAmount(String(editingCost.amount));
      setDescription(editingCost.description || '');
      setDate(editingCost.date);
      setItemName(editingCost.description || '');
      setSupplier(editingCost.supplier || '');
      setQuantity(editingCost.quantity ? String(editingCost.quantity) : '');
      setUnitCost(editingCost.unit_cost ? String(editingCost.unit_cost) : '');
      setWorkerName(editingCost.worker_name || '');
      setHours(editingCost.hours ? String(editingCost.hours) : '');
      setHourlyRate(editingCost.hourly_rate ? String(editingCost.hourly_rate) : '');
      setEquipmentName(editingCost.equipment_name || '');
      setRentalDays(editingCost.rental_days ? String(editingCost.rental_days) : '');
      setDailyRate(editingCost.daily_rate ? String(editingCost.daily_rate) : '');
      setContractorName(editingCost.contractor_name || '');
      setInvoiceReference(editingCost.invoice_reference || '');
      setMaterialLaborCost(editingCost.labor_cost ? String(editingCost.labor_cost) : '');
      setTransportCost(editingCost.transport_cost ? String(editingCost.transport_cost) : '');
    } else if (defaultCostType) {
      setCostType(defaultCostType);
    }
  }, [editingCost, defaultCostType]);

  // Reset form when closed
  useEffect(() => {
    if (!open) {
      resetForm();
    }
  }, [open]);

  // Fetch materials for dropdown
  useEffect(() => {
    if (costType === 'materials' && user) {
      const fetchMaterials = async () => {
        try {
          const { data: profile } = await supabase
            .from('profiles')
            .select('company_id')
            .eq('user_id', user.id)
            .single();

          if (profile?.company_id) {
            const { data } = await supabase
              .from('materials')
              .select('id, name, default_unit_cost')
              .eq('company_id', profile.company_id)
              .order('name');
            setMaterials(data || []);
          }
        } catch (e) {
          console.error('Failed to fetch materials', e);
        }
      };
      
      fetchMaterials();
    }
  }, [costType, user]);

  // Calculate amount for labor and equipment
  useEffect(() => {
    if (costType === 'labor' && hours && hourlyRate) {
      setAmount((parseFloat(hours) * parseFloat(hourlyRate)).toFixed(2));
    } else if (costType === 'equipment' && rentalDays && dailyRate) {
      setAmount((parseFloat(rentalDays) * parseFloat(dailyRate)).toFixed(2));
    } else if (costType === 'materials' && quantity && unitCost) {
      const baseAmount = parseFloat(quantity) * parseFloat(unitCost);
      const extraLabor = parseFloat(materialLaborCost || '0');
      const extraTransport = parseFloat(transportCost || '0');
      setAmount((baseAmount + extraLabor + extraTransport).toFixed(2));
    }
  }, [costType, hours, hourlyRate, rentalDays, dailyRate, quantity, unitCost, materialLaborCost, transportCost]);

  const resetForm = () => {
    setAmount('');
    setDescription('');
    setDate(new Date().toISOString().split('T')[0]);
    setItemName('');
    setSupplier('');
    setQuantity('');
    setUnitCost('');
    setWorkerName('');
    setHours('');
    setHourlyRate('');
    setEquipmentName('');
    setRentalDays('');
    setDailyRate('');
    setContractorName('');
    setInvoiceReference('');
    setMaterialLaborCost('');
    setTransportCost('');
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!amount || parseFloat(amount) <= 0) {
      toast.error('Please enter a valid amount');
      return;
    }

    // For materials, require item name
    if (costType === 'materials' && !itemName.trim()) {
      toast.error('Please enter an item name');
      return;
    }

    // Use item name as description for materials if no description provided
    const finalDescription = costType === 'materials' && !description.trim() 
      ? itemName.trim() 
      : description.trim();

    if (!finalDescription) {
      toast.error('Please enter a description');
      return;
    }

    setLoading(true);

    try {
      const costData = {
        project_id: projectId,
        cost_type: costType as 'materials' | 'labor' | 'equipment' | 'subcontractors',
        amount: parseFloat(amount),
        description: finalDescription,
        date,
        created_by: user!.id,
        supplier: costType === 'materials' ? (supplier || null) : null,
        quantity: costType === 'materials' && quantity ? parseFloat(quantity) : null,
        unit_cost: costType === 'materials' && unitCost ? parseFloat(unitCost) : null,
        worker_name: costType === 'labor' ? (workerName || null) : null,
        hours: costType === 'labor' && hours ? parseFloat(hours) : null,
        hourly_rate: costType === 'labor' && hourlyRate ? parseFloat(hourlyRate) : null,
        equipment_name: costType === 'equipment' ? (equipmentName || null) : null,
        rental_days: costType === 'equipment' && rentalDays ? parseInt(rentalDays) : null,
        daily_rate: costType === 'equipment' && dailyRate ? parseFloat(dailyRate) : null,
        contractor_name: costType === 'subcontractors' ? (contractorName || null) : null,
        invoice_reference: costType === 'subcontractors' ? (invoiceReference || null) : null,
        labor_cost: costType === 'materials' && materialLaborCost ? parseFloat(materialLaborCost) : null,
        transport_cost: costType === 'materials' && transportCost ? parseFloat(transportCost) : null,
      };

      if (editingCost) {
        // Update existing cost
        const { error } = await supabase
          .from('costs')
          .update(costData)
          .eq('id', editingCost.id);

        if (error) throw error;
        toast.success('Cost updated successfully!');
      } else {
        // Insert new cost
        const { error } = await supabase.from('costs').insert(costData);

        if (error) throw error;
        toast.success('Cost added successfully!');
      }

      resetForm();
      onOpenChange(false);
      onSuccess();
    } catch (error) {
      console.error('Failed to add cost:', error);
      toast.error('Failed to add cost');
    } finally {
      setLoading(false);
    }
  };

  const Icon = costTypeIcons[costType as keyof typeof costTypeIcons];

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="sm:max-w-md overflow-y-auto custom-scrollbar">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2 font-heading">
            <Icon className="w-5 h-5 text-destructive" />
            {editingCost ? 'EDIT' : 'ADD'} {costTypeLabels[costType as keyof typeof costTypeLabels].toUpperCase()} COST
          </SheetTitle>
        </SheetHeader>

        <form onSubmit={handleSubmit} className="space-y-6 mt-6">
          {/* Cost Type Selector - disabled when editing */}
          <div className="space-y-2">
            <Label>Cost Type</Label>
            <Select value={costType} onValueChange={setCostType} disabled={!!editingCost}>
              <SelectTrigger className="bg-input border-border">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="materials">
                  <span className="flex items-center gap-2">
                    <Package className="w-4 h-4" /> Materials
                  </span>
                </SelectItem>
                <SelectItem value="labor">
                  <span className="flex items-center gap-2">
                    <Users className="w-4 h-4" /> Labor
                  </span>
                </SelectItem>
                <SelectItem value="equipment">
                  <span className="flex items-center gap-2">
                    <Truck className="w-4 h-4" /> Equipment
                  </span>
                </SelectItem>
                <SelectItem value="subcontractors">
                  <span className="flex items-center gap-2">
                    <Hammer className="w-4 h-4" /> Subcontractors
                  </span>
                </SelectItem>
              </SelectContent>
            </Select>
          </div>

          {/* Date */}
          <div className="space-y-2">
            <Label htmlFor="date">Date</Label>
            <Input
              id="date"
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
              className="bg-input border-border"
              disabled={loading}
            />
          </div>

          {/* Type-specific fields */}
          {costType === 'materials' && (
            <>
              <div className="space-y-2">
                <Label htmlFor="itemName">Material *</Label>
                <Select 
                  value={itemName} 
                  onValueChange={(val) => {
                    setItemName(val);
                    const mat = materials.find(m => m.name === val);
                    if (mat && mat.default_unit_cost !== null && !unitCost) {
                      setUnitCost(String(mat.default_unit_cost));
                    }
                  }} 
                  disabled={loading}
                >
                  <SelectTrigger className="bg-input border-border" id="itemName">
                    <SelectValue placeholder="Select a material" />
                  </SelectTrigger>
                  <SelectContent>
                    {materials.length === 0 ? (
                      <SelectItem value="_empty" disabled>No materials in catalogue</SelectItem>
                    ) : (
                      <>
                        {materials.map(mat => (
                          <SelectItem key={mat.id} value={mat.name}>{mat.name}</SelectItem>
                        ))}
                        {editingCost && itemName && !materials.find(m => m.name === itemName) && (
                          <SelectItem value={itemName}>{itemName} (Legacy Item)</SelectItem>
                        )}
                      </>
                    )}
                  </SelectContent>
                </Select>
                {materials.length === 0 && (
                  <p className="text-xs text-muted-foreground mt-1">
                    Add materials from the Materials menu before logging costs.
                  </p>
                )}
              </div>
              <div className="space-y-2">
                <Label htmlFor="supplier">Supplier</Label>
                <Input
                  id="supplier"
                  placeholder="Hardware Store Name"
                  value={supplier}
                  onChange={(e) => setSupplier(e.target.value)}
                  className="bg-input border-border"
                  disabled={loading}
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="quantity">Quantity</Label>
                  <Input
                    id="quantity"
                    type="number"
                    step="0.01"
                    placeholder="100"
                    value={quantity}
                    onChange={(e) => setQuantity(e.target.value)}
                    className="bg-input border-border"
                    disabled={loading}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="unitCost">Unit Cost (KSH)</Label>
                  <Input
                    id="unitCost"
                    type="number"
                    step="0.01"
                    placeholder="2500"
                    value={unitCost}
                    onChange={(e) => setUnitCost(e.target.value)}
                    className="bg-input border-border"
                    disabled={loading}
                  />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="materialLaborCost">Extra Labor Cost (KSH)</Label>
                  <Input
                    id="materialLaborCost"
                    type="number"
                    step="0.01"
                    placeholder="0"
                    value={materialLaborCost}
                    onChange={(e) => setMaterialLaborCost(e.target.value)}
                    className="bg-input border-border"
                    disabled={loading}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="transportCost">Transport Cost (KSH)</Label>
                  <Input
                    id="transportCost"
                    type="number"
                    step="0.01"
                    placeholder="0"
                    value={transportCost}
                    onChange={(e) => setTransportCost(e.target.value)}
                    className="bg-input border-border"
                    disabled={loading}
                  />
                </div>
              </div>
            </>
          )}

          {costType === 'labor' && (
            <>
              <div className="space-y-2">
                <Label htmlFor="workerName">Worker / Crew Name</Label>
                <Input
                  id="workerName"
                  placeholder="Framing Crew A"
                  value={workerName}
                  onChange={(e) => setWorkerName(e.target.value)}
                  className="bg-input border-border"
                  disabled={loading}
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="hours">Days</Label>
                  <Input
                    id="hours"
                    type="number"
                    step="0.5"
                    placeholder="1"
                    value={hours}
                    onChange={(e) => setHours(e.target.value)}
                    className="bg-input border-border"
                    disabled={loading}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="hourlyRate">Daily Rate (KSH)</Label>
                  <Input
                    id="hourlyRate"
                    type="number"
                    step="0.01"
                    placeholder="1500"
                    value={hourlyRate}
                    onChange={(e) => setHourlyRate(e.target.value)}
                    className="bg-input border-border"
                    disabled={loading}
                  />
                </div>
              </div>
            </>
          )}

          {costType === 'equipment' && (
            <>
              <div className="space-y-2">
                <Label htmlFor="equipmentName">Equipment Name</Label>
                <Input
                  id="equipmentName"
                  placeholder="Excavator CAT 320"
                  value={equipmentName}
                  onChange={(e) => setEquipmentName(e.target.value)}
                  className="bg-input border-border"
                  disabled={loading}
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="rentalDays">Rental Days</Label>
                  <Input
                    id="rentalDays"
                    type="number"
                    placeholder="5"
                    value={rentalDays}
                    onChange={(e) => setRentalDays(e.target.value)}
                    className="bg-input border-border"
                    disabled={loading}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="dailyRate">Daily Rate (KSH)</Label>
                  <Input
                    id="dailyRate"
                    type="number"
                    step="0.01"
                    placeholder="35000"
                    value={dailyRate}
                    onChange={(e) => setDailyRate(e.target.value)}
                    className="bg-input border-border"
                    disabled={loading}
                  />
                </div>
              </div>
            </>
          )}

          {costType === 'subcontractors' && (
            <>
              <div className="space-y-2">
                <Label htmlFor="contractorName">Contractor Name</Label>
                <Input
                  id="contractorName"
                  placeholder="Elite Plumbing Co."
                  value={contractorName}
                  onChange={(e) => setContractorName(e.target.value)}
                  className="bg-input border-border"
                  disabled={loading}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="invoiceReference">Invoice Reference</Label>
                <Input
                  id="invoiceReference"
                  placeholder="INV-2024-001"
                  value={invoiceReference}
                  onChange={(e) => setInvoiceReference(e.target.value)}
                  className="bg-input border-border"
                  disabled={loading}
                />
              </div>
            </>
          )}

          {/* Description */}
          <div className="space-y-2">
            <Label htmlFor="description">Description *</Label>
            <Textarea
              id="description"
              placeholder="What was this cost for?"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              className="bg-input border-border"
              disabled={loading}
            />
          </div>

          {/* Amount */}
          <div className="space-y-2">
            <Label htmlFor="amount">Total Amount (KSH) *</Label>
            <Input
              id="amount"
              type="number"
              step="0.01"
              placeholder="0"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="bg-input border-border text-xl font-heading"
              disabled={loading}
            />
          </div>

          {/* Submit */}
          <Button
            type="submit"
            className="w-full tactile-press"
            disabled={loading}
          >
            {loading ? (
              <Loader2 className="w-4 h-4 animate-spin mr-2" />
            ) : null}
            {editingCost ? 'Update Cost' : 'Add Cost'}
          </Button>
        </form>
      </SheetContent>
    </Sheet>
  );
}
