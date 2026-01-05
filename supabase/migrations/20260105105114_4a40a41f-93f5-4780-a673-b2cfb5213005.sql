-- Create password reset tokens table
CREATE TABLE public.password_reset_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL,
  token uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '1 hour'),
  used_at timestamptz
);

-- Index for token lookup
CREATE INDEX idx_password_reset_tokens_token ON public.password_reset_tokens(token);

-- Index for cleanup of expired tokens
CREATE INDEX idx_password_reset_tokens_expires ON public.password_reset_tokens(expires_at);

-- RLS: No public access (only edge functions with service role can access)
ALTER TABLE public.password_reset_tokens ENABLE ROW LEVEL SECURITY;