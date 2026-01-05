-- Create the invitations table
CREATE TABLE public.invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  email text NOT NULL,
  role public.app_role NOT NULL DEFAULT 'viewer',
  invited_by uuid NOT NULL,
  token uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  accepted_at timestamptz NULL,
  CONSTRAINT invitations_token_unique UNIQUE (token)
);

-- Create indexes for better query performance
CREATE INDEX idx_invitations_company_id ON public.invitations(company_id);
CREATE INDEX idx_invitations_email ON public.invitations(email);
CREATE INDEX idx_invitations_token ON public.invitations(token);
CREATE INDEX idx_invitations_expires_at ON public.invitations(expires_at);

-- Enable RLS
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Managers can manage invitations for their company
CREATE POLICY "Managers can view invitations in their company"
ON public.invitations
FOR SELECT
USING (has_role(auth.uid(), company_id, 'manager'));

CREATE POLICY "Managers can create invitations in their company"
ON public.invitations
FOR INSERT
WITH CHECK (
  company_id = get_user_company_id(auth.uid()) 
  AND has_role(auth.uid(), company_id, 'manager')
);

CREATE POLICY "Managers can delete invitations in their company"
ON public.invitations
FOR DELETE
USING (has_role(auth.uid(), company_id, 'manager'));

-- Create a SECURITY DEFINER function to safely get invitation details without auth
-- This allows the /auth?invite=TOKEN page to work before the user is logged in
CREATE OR REPLACE FUNCTION public.get_invitation_details(_token uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _invitation RECORD;
  _company_name text;
BEGIN
  -- Get the invitation if valid (not accepted, not expired)
  SELECT * INTO _invitation
  FROM public.invitations
  WHERE token = _token
    AND accepted_at IS NULL
    AND expires_at > now();
    
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired invitation');
  END IF;

  -- Get company name
  SELECT name INTO _company_name
  FROM public.companies
  WHERE id = _invitation.company_id;

  RETURN jsonb_build_object(
    'success', true,
    'email', _invitation.email,
    'role', _invitation.role,
    'company_id', _invitation.company_id,
    'company_name', _company_name
  );
END;
$$;