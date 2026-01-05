-- ConstructLedger Database Schema
-- Multi-tenant construction management system

-- 1. Create role enum for access control
CREATE TYPE public.app_role AS ENUM ('manager', 'viewer');

-- 2. Create cost type enum
CREATE TYPE public.cost_type AS ENUM ('materials', 'labor', 'equipment', 'subcontractors');

-- 3. Companies table (tenant isolation)
CREATE TABLE public.companies (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- 4. User profiles linked to companies
CREATE TABLE public.profiles (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  full_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);

-- 5. User roles table (separate from profiles for security)
CREATE TABLE public.user_roles (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  role app_role NOT NULL DEFAULT 'viewer',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id, company_id)
);

-- 6. Projects table (tied to company)
CREATE TABLE public.projects (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  client_name TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'on_hold')),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- 7. Income table (client payments)
CREATE TABLE public.income (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  amount DECIMAL(12,2) NOT NULL,
  description TEXT,
  invoice_reference TEXT,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- 8. Costs table (materials, labor, equipment, subcontractors)
CREATE TABLE public.costs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  cost_type cost_type NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  description TEXT NOT NULL,
  -- Common fields
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  -- Materials specific
  supplier TEXT,
  quantity DECIMAL(10,2),
  unit_cost DECIMAL(12,2),
  -- Labor specific
  worker_name TEXT,
  hours DECIMAL(6,2),
  hourly_rate DECIMAL(10,2),
  -- Equipment specific
  equipment_name TEXT,
  rental_days INTEGER,
  daily_rate DECIMAL(10,2),
  -- Subcontractor specific
  contractor_name TEXT,
  invoice_reference TEXT,
  -- Metadata
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- 9. Enable Row Level Security on all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.income ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.costs ENABLE ROW LEVEL SECURITY;

-- 10. Security definer function to check user role
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _company_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND company_id = _company_id
      AND role = _role
  )
$$;

-- 11. Function to get user's company_id
CREATE OR REPLACE FUNCTION public.get_user_company_id(_user_id UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT company_id FROM public.profiles WHERE user_id = _user_id LIMIT 1
$$;

-- 12. RLS Policies for companies
CREATE POLICY "Users can view their own company"
  ON public.companies FOR SELECT
  USING (id = public.get_user_company_id(auth.uid()));

CREATE POLICY "Managers can update their company"
  ON public.companies FOR UPDATE
  USING (public.has_role(auth.uid(), id, 'manager'));

-- 13. RLS Policies for profiles
CREATE POLICY "Users can view profiles in their company"
  ON public.profiles FOR SELECT
  USING (company_id = public.get_user_company_id(auth.uid()));

CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE
  USING (user_id = auth.uid());

CREATE POLICY "Managers can insert profiles in their company"
  ON public.profiles FOR INSERT
  WITH CHECK (company_id = public.get_user_company_id(auth.uid()) AND public.has_role(auth.uid(), company_id, 'manager'));

-- 14. RLS Policies for user_roles
CREATE POLICY "Users can view roles in their company"
  ON public.user_roles FOR SELECT
  USING (company_id = public.get_user_company_id(auth.uid()));

CREATE POLICY "Managers can manage roles in their company"
  ON public.user_roles FOR ALL
  USING (public.has_role(auth.uid(), company_id, 'manager'));

-- 15. RLS Policies for projects
CREATE POLICY "Users can view projects in their company"
  ON public.projects FOR SELECT
  USING (company_id = public.get_user_company_id(auth.uid()));

CREATE POLICY "Managers can insert projects"
  ON public.projects FOR INSERT
  WITH CHECK (company_id = public.get_user_company_id(auth.uid()) AND public.has_role(auth.uid(), company_id, 'manager'));

CREATE POLICY "Managers can update projects"
  ON public.projects FOR UPDATE
  USING (public.has_role(auth.uid(), company_id, 'manager'));

CREATE POLICY "Managers can delete projects"
  ON public.projects FOR DELETE
  USING (public.has_role(auth.uid(), company_id, 'manager'));

-- 16. RLS Policies for income
CREATE POLICY "Users can view income in their projects"
  ON public.income FOR SELECT
  USING (project_id IN (SELECT id FROM public.projects WHERE company_id = public.get_user_company_id(auth.uid())));

CREATE POLICY "Managers can insert income"
  ON public.income FOR INSERT
  WITH CHECK (
    project_id IN (
      SELECT p.id FROM public.projects p 
      WHERE p.company_id = public.get_user_company_id(auth.uid())
    ) AND public.has_role(auth.uid(), public.get_user_company_id(auth.uid()), 'manager')
  );

CREATE POLICY "Managers can update income"
  ON public.income FOR UPDATE
  USING (
    project_id IN (
      SELECT p.id FROM public.projects p 
      WHERE public.has_role(auth.uid(), p.company_id, 'manager')
    )
  );

CREATE POLICY "Managers can delete income"
  ON public.income FOR DELETE
  USING (
    project_id IN (
      SELECT p.id FROM public.projects p 
      WHERE public.has_role(auth.uid(), p.company_id, 'manager')
    )
  );

-- 17. RLS Policies for costs
CREATE POLICY "Users can view costs in their projects"
  ON public.costs FOR SELECT
  USING (project_id IN (SELECT id FROM public.projects WHERE company_id = public.get_user_company_id(auth.uid())));

CREATE POLICY "Managers can insert costs"
  ON public.costs FOR INSERT
  WITH CHECK (
    project_id IN (
      SELECT p.id FROM public.projects p 
      WHERE p.company_id = public.get_user_company_id(auth.uid())
    ) AND public.has_role(auth.uid(), public.get_user_company_id(auth.uid()), 'manager')
  );

CREATE POLICY "Managers can update costs"
  ON public.costs FOR UPDATE
  USING (
    project_id IN (
      SELECT p.id FROM public.projects p 
      WHERE public.has_role(auth.uid(), p.company_id, 'manager')
    )
  );

CREATE POLICY "Managers can delete costs"
  ON public.costs FOR DELETE
  USING (
    project_id IN (
      SELECT p.id FROM public.projects p 
      WHERE public.has_role(auth.uid(), p.company_id, 'manager')
    )
  );

-- 18. Updated_at trigger function
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- 19. Add updated_at triggers
CREATE TRIGGER update_companies_updated_at
  BEFORE UPDATE ON public.companies
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_projects_updated_at
  BEFORE UPDATE ON public.projects
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_income_updated_at
  BEFORE UPDATE ON public.income
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_costs_updated_at
  BEFORE UPDATE ON public.costs
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 20. Create indexes for performance
CREATE INDEX idx_profiles_company_id ON public.profiles(company_id);
CREATE INDEX idx_profiles_user_id ON public.profiles(user_id);
CREATE INDEX idx_user_roles_user_id ON public.user_roles(user_id);
CREATE INDEX idx_user_roles_company_id ON public.user_roles(company_id);
CREATE INDEX idx_projects_company_id ON public.projects(company_id);
CREATE INDEX idx_income_project_id ON public.income(project_id);
CREATE INDEX idx_costs_project_id ON public.costs(project_id);
CREATE INDEX idx_costs_type ON public.costs(cost_type);