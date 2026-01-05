import { useState } from 'react';
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
import { toast } from 'sonner';
import { Loader2, DollarSign } from 'lucide-react';

interface AddIncomeSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  projectId: string;
  onSuccess: () => void;
}

export default function AddIncomeSheet({
  open,
  onOpenChange,
  projectId,
  onSuccess,
}: AddIncomeSheetProps) {
  const { user } = useAuth();
  const [loading, setLoading] = useState(false);
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [invoiceReference, setInvoiceReference] = useState('');
  const [date, setDate] = useState(new Date().toISOString().split('T')[0]);

  const resetForm = () => {
    setAmount('');
    setDescription('');
    setInvoiceReference('');
    setDate(new Date().toISOString().split('T')[0]);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!amount || parseFloat(amount) <= 0) {
      toast.error('Please enter a valid amount');
      return;
    }

    setLoading(true);

    try {
      const { error } = await supabase.from('income').insert({
        project_id: projectId,
        amount: parseFloat(amount),
        description: description.trim() || null,
        invoice_reference: invoiceReference.trim() || null,
        date,
        created_by: user!.id,
      });

      if (error) throw error;

      toast.success('Income added successfully!');
      resetForm();
      onOpenChange(false);
      onSuccess();
    } catch (error) {
      toast.error('Failed to add income');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="sm:max-w-md">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2 font-heading">
            <DollarSign className="w-5 h-5 text-success" />
            ADD CLIENT PAYMENT
          </SheetTitle>
        </SheetHeader>

        <form onSubmit={handleSubmit} className="space-y-6 mt-6">
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

          {/* Invoice Reference */}
          <div className="space-y-2">
            <Label htmlFor="invoiceReference">Invoice / Reference #</Label>
            <Input
              id="invoiceReference"
              placeholder="INV-2024-001"
              value={invoiceReference}
              onChange={(e) => setInvoiceReference(e.target.value)}
              className="bg-input border-border"
              disabled={loading}
            />
          </div>

          {/* Description */}
          <div className="space-y-2">
            <Label htmlFor="description">Description</Label>
            <Textarea
              id="description"
              placeholder="Progress payment for phase 1..."
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              className="bg-input border-border"
              disabled={loading}
            />
          </div>

          {/* Amount */}
          <div className="space-y-2">
            <Label htmlFor="amount">Amount ($) *</Label>
            <Input
              id="amount"
              type="number"
              step="0.01"
              placeholder="0.00"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="bg-input border-border text-xl font-heading text-success"
              disabled={loading}
            />
          </div>

          {/* Submit */}
          <Button
            type="submit"
            className="w-full tactile-press bg-success hover:bg-success/90 text-success-foreground"
            disabled={loading}
          >
            {loading ? (
              <Loader2 className="w-4 h-4 animate-spin mr-2" />
            ) : null}
            Add Income
          </Button>
        </form>
      </SheetContent>
    </Sheet>
  );
}
