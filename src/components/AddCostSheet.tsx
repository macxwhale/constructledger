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

interface AddCostSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  projectId: string;
  defaultCostType?: string | null;
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
  onSuccess,
}: AddCostSheetProps) {
  const { user } = useAuth();
  const [loading, setLoading] = useState(false);
  const [costType, setCostType] = useState(defaultCostType || 'materials');
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [date, setDate] = useState(new Date().toISOString().split('T')[0]);

  // Materials fields
  const [itemName, setItemName] = useState('');
  const [supplier, setSupplier] = useState('');
  const [quantity, setQuantity] = useState('');
  const [unitCost, setUnitCost] = useState('');

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

  useEffect(() => {
    if (defaultCostType) {
      setCostType(defaultCostType);
    }
  }, [defaultCostType]);

  // Calculate amount for labor and equipment
  useEffect(() => {
    if (costType === 'labor' && hours && hourlyRate) {
      setAmount((parseFloat(hours) * parseFloat(hourlyRate)).toFixed(2));
    } else if (costType === 'equipment' && rentalDays && dailyRate) {
      setAmount((parseFloat(rentalDays) * parseFloat(dailyRate)).toFixed(2));
    } else if (costType === 'materials' && quantity && unitCost) {
      setAmount((parseFloat(quantity) * parseFloat(unitCost)).toFixed(2));
    }
  }, [costType, hours, hourlyRate, rentalDays, dailyRate, quantity, unitCost]);

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
        // Materials fields
        supplier: costType === 'materials' ? (supplier || null) : null,
        quantity: costType === 'materials' && quantity ? parseFloat(quantity) : null,
        unit_cost: costType === 'materials' && unitCost ? parseFloat(unitCost) : null,
        // Labor fields
        worker_name: costType === 'labor' ? (workerName || null) : null,
        hours: costType === 'labor' && hours ? parseFloat(hours) : null,
        hourly_rate: costType === 'labor' && hourlyRate ? parseFloat(hourlyRate) : null,
        // Equipment fields
        equipment_name: costType === 'equipment' ? (equipmentName || null) : null,
        rental_days: costType === 'equipment' && rentalDays ? parseInt(rentalDays) : null,
        daily_rate: costType === 'equipment' && dailyRate ? parseFloat(dailyRate) : null,
        // Subcontractor fields
        contractor_name: costType === 'subcontractors' ? (contractorName || null) : null,
        invoice_reference: costType === 'subcontractors' ? (invoiceReference || null) : null,
      };

      const { error } = await supabase.from('costs').insert(costData);

      if (error) throw error;

      toast.success('Cost added successfully!');
      resetForm();
      onOpenChange(false);
      onSuccess();
    } catch (error) {
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
            ADD {costTypeLabels[costType as keyof typeof costTypeLabels].toUpperCase()} COST
          </SheetTitle>
        </SheetHeader>

        <form onSubmit={handleSubmit} className="space-y-6 mt-6">
          {/* Cost Type Selector */}
          <div className="space-y-2">
            <Label>Cost Type</Label>
            <Select value={costType} onValueChange={setCostType}>
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
                <Label htmlFor="itemName">Item Name *</Label>
                <Input
                  id="itemName"
                  placeholder="e.g. Logs, Cables, Cement, Nails..."
                  value={itemName}
                  onChange={(e) => setItemName(e.target.value)}
                  className="bg-input border-border"
                  disabled={loading}
                  required
                />
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
                  <Label htmlFor="hours">Hours</Label>
                  <Input
                    id="hours"
                    type="number"
                    step="0.5"
                    placeholder="8"
                    value={hours}
                    onChange={(e) => setHours(e.target.value)}
                    className="bg-input border-border"
                    disabled={loading}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="hourlyRate">Hourly Rate (KSH)</Label>
                  <Input
                    id="hourlyRate"
                    type="number"
                    step="0.01"
                    placeholder="500"
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
            Add Cost
          </Button>
        </form>
      </SheetContent>
    </Sheet>
  );
}
