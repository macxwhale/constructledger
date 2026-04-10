
CREATE TABLE public.materials (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  unit TEXT,
  default_unit_cost NUMERIC,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.materials ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view materials in their company"
  ON public.materials FOR SELECT
  USING (company_id = get_user_company_id(auth.uid()));

CREATE POLICY "Managers can insert materials"
  ON public.materials FOR INSERT
  WITH CHECK (company_id = get_user_company_id(auth.uid()) AND has_role(auth.uid(), company_id, 'manager'::app_role));

CREATE POLICY "Managers can update materials"
  ON public.materials FOR UPDATE
  USING (has_role(auth.uid(), company_id, 'manager'::app_role));

CREATE POLICY "Managers can delete materials"
  ON public.materials FOR DELETE
  USING (has_role(auth.uid(), company_id, 'manager'::app_role));

CREATE TRIGGER update_materials_updated_at
  BEFORE UPDATE ON public.materials
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
