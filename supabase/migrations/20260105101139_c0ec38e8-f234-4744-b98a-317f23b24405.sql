-- Fix accept_invitation function to handle profiles without unique constraint
CREATE OR REPLACE FUNCTION public.accept_invitation(_token UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _invitation RECORD;
  _user_id UUID;
  _existing_profile UUID;
BEGIN
  _user_id := auth.uid();
  
  IF _user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Get the invitation
  SELECT * INTO _invitation
  FROM public.invitations
  WHERE token = _token
    AND accepted_at IS NULL
    AND expires_at > now();
    
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired invitation');
  END IF;

  -- Check if user already has a profile
  SELECT id INTO _existing_profile FROM public.profiles WHERE user_id = _user_id;
  
  IF _existing_profile IS NOT NULL THEN
    -- Update existing profile to new company
    UPDATE public.profiles SET company_id = _invitation.company_id WHERE user_id = _user_id;
  ELSE
    -- Create new profile
    INSERT INTO public.profiles (user_id, company_id, full_name)
    VALUES (_user_id, _invitation.company_id, COALESCE((SELECT raw_user_meta_data->>'full_name' FROM auth.users WHERE id = _user_id), ''));
  END IF;

  -- Delete any existing roles for this user
  DELETE FROM public.user_roles WHERE user_id = _user_id;
  
  -- Create user role in new company
  INSERT INTO public.user_roles (user_id, company_id, role)
  VALUES (_user_id, _invitation.company_id, _invitation.role);

  -- Mark invitation as accepted
  UPDATE public.invitations
  SET accepted_at = now()
  WHERE token = _token;

  RETURN jsonb_build_object('success', true, 'company_id', _invitation.company_id);
END;
$$;