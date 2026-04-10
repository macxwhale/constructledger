-- Create materials table
CREATE TABLE public.materials (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  unit TEXT,
  default_unit_cost DECIMAL(12,2),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Indexes for performance
CREATE INDEX idx_materials_company_id ON public.materials(company_id);

-- Enable RLS
ALTER TABLE public.materials ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view materials in their company"
  ON public.materials FOR SELECT
  USING (company_id = public.get_user_company_id(auth.uid()));

CREATE POLICY "Managers can insert materials"
  ON public.materials FOR INSERT
  WITH CHECK (
    company_id = public.get_user_company_id(auth.uid()) 
    AND public.has_role(auth.uid(), company_id, 'manager')
  );

CREATE POLICY "Managers can update materials"
  ON public.materials FOR UPDATE
  USING (
    company_id = public.get_user_company_id(auth.uid()) 
    AND public.has_role(auth.uid(), company_id, 'manager')
  );

CREATE POLICY "Managers can delete materials"
  ON public.materials FOR DELETE
  USING (
    company_id = public.get_user_company_id(auth.uid()) 
    AND public.has_role(auth.uid(), company_id, 'manager')
  );

-- Trigger for updated_at
CREATE TRIGGER update_materials_updated_at
  BEFORE UPDATE ON public.materials
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
