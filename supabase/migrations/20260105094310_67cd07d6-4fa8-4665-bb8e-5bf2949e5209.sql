-- Allow authenticated users to insert companies (they'll become the manager)
CREATE POLICY "Authenticated users can create companies"
ON public.companies
FOR INSERT
TO authenticated
WITH CHECK (true);

-- Also allow the initial signup flow - we need a function to handle this securely
CREATE OR REPLACE FUNCTION public.handle_new_user_signup(
  _company_name text,
  _full_name text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _company_id uuid;
BEGIN
  -- Create the company
  INSERT INTO public.companies (name)
  VALUES (_company_name)
  RETURNING id INTO _company_id;
  
  -- Create the profile
  INSERT INTO public.profiles (user_id, company_id, full_name)
  VALUES (auth.uid(), _company_id, _full_name);
  
  -- Assign manager role
  INSERT INTO public.user_roles (user_id, company_id, role)
  VALUES (auth.uid(), _company_id, 'manager');
  
  RETURN _company_id;
END;
$$;