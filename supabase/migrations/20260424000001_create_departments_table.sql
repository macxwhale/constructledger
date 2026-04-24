-- Create departments table
CREATE TABLE public.departments (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(company_id, name)
);

-- Add department_id to costs
ALTER TABLE public.costs ADD COLUMN department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL;

-- Enable RLS
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view departments in their company"
  ON public.departments FOR SELECT
  USING (company_id = public.get_user_company_id(auth.uid()));

CREATE POLICY "Managers can manage departments"
  ON public.departments FOR ALL
  USING (
    company_id = public.get_user_company_id(auth.uid()) 
    AND public.has_role(auth.uid(), company_id, 'manager')
  );

-- Trigger for updated_at
CREATE TRIGGER update_departments_updated_at
  BEFORE UPDATE ON public.departments
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Populate existing companies with predefined departments
INSERT INTO public.departments (company_id, name)
SELECT c.id, d.name
FROM public.companies c
CROSS JOIN (
  VALUES 
    ('ICT & Security'),
    ('Construction'),
    ('Electrical'),
    ('Fire Alarm'),
    ('AC'),
    ('Substructure (Foundation)'),
    ('Superstructure (Walls & Columns)'),
    ('Roofing'),
    ('Plastering & Finishes'),
    ('Plumbing & Drainage'),
    ('Joinery & Metalwork'),
    ('External Works')
) AS d(name)
ON CONFLICT (company_id, name) DO NOTHING;
