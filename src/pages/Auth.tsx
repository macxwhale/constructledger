import { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';
import { Loader2, HardHat, Building2, Mail, UserPlus } from 'lucide-react';
import { z } from 'zod';

const signInSchema = z.object({
  email: z.string().email('Invalid email address'),
  password: z.string().min(6, 'Password must be at least 6 characters'),
});

const signUpSchema = signInSchema.extend({
  companyName: z.string().min(2, 'Company name must be at least 2 characters'),
  fullName: z.string().min(2, 'Full name must be at least 2 characters'),
});

const inviteSignUpSchema = signInSchema.extend({
  fullName: z.string().min(2, 'Full name must be at least 2 characters'),
});

interface InvitationData {
  email: string;
  role: string;
  company_name: string;
}

export default function Auth() {
  const [searchParams] = useSearchParams();
  const inviteToken = searchParams.get('invite');
  
  const [isSignUp, setIsSignUp] = useState(false);
  const [loading, setLoading] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [companyName, setCompanyName] = useState('');
  const [fullName, setFullName] = useState('');
  const [showForgotPassword, setShowForgotPassword] = useState(false);
  const [resetEmailSent, setResetEmailSent] = useState(false);
  
  // Invitation state
  const [invitationData, setInvitationData] = useState<InvitationData | null>(null);
  const [loadingInvitation, setLoadingInvitation] = useState(false);
  
  const { signIn, signUp } = useAuth();
  const navigate = useNavigate();

  // Check for invite token on mount
  useEffect(() => {
    if (inviteToken) {
      fetchInvitation(inviteToken);
    }
  }, [inviteToken]);

  const fetchInvitation = async (token: string) => {
    setLoadingInvitation(true);
    try {
      // Use raw query since types haven't been regenerated yet
      const { data, error } = await (supabase as any)
        .from('invitations')
        .select('email, role, company_id')
        .eq('token', token)
        .is('accepted_at', null)
        .gt('expires_at', new Date().toISOString())
        .single();

      if (error || !data) {
        toast.error('Invalid or expired invitation link');
        navigate('/auth');
        return;
      }

      // Get company name separately
      const { data: companyData } = await supabase
        .from('companies')
        .select('name')
        .eq('id', (data as any).company_id)
        .single();

      setInvitationData({
        email: (data as any).email,
        role: (data as any).role,
        company_name: companyData?.name || 'Unknown Company',
      });
      setEmail((data as any).email);
      setIsSignUp(true);
    } catch (error) {
      toast.error('Failed to load invitation');
    } finally {
      setLoadingInvitation(false);
    }
  };

  const handleForgotPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      const emailValidation = z.string().email().safeParse(email);
      if (!emailValidation.success) {
        toast.error('Please enter a valid email address');
        setLoading(false);
        return;
      }

      const { error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: `${window.location.origin}/reset-password`,
      });

      if (error) throw error;

      setResetEmailSent(true);
      toast.success('Password reset email sent! Check your inbox.');
    } catch (error: any) {
      toast.error(error.message || 'Failed to send reset email');
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      if (isSignUp) {
        // If joining via invitation
        if (invitationData) {
          const validation = inviteSignUpSchema.safeParse({ email, password, fullName });
          if (!validation.success) {
            toast.error(validation.error.errors[0].message);
            setLoading(false);
            return;
          }

          // Sign up the user
          const { data: authData, error: authError } = await supabase.auth.signUp({
            email,
            password,
            options: {
              emailRedirectTo: `${window.location.origin}/`,
              data: { full_name: fullName },
            },
          });

          if (authError) throw authError;

          if (authData.user && authData.session) {
            // Accept the invitation
            const { data: result, error: acceptError } = await supabase.rpc('accept_invitation', {
              _token: inviteToken,
            });

            if (acceptError) {
              console.error('Accept invitation error:', acceptError);
              throw new Error('Failed to accept invitation');
            }

            const acceptResult = result as { success: boolean; error?: string };
            if (!acceptResult.success) {
              throw new Error(acceptResult.error || 'Failed to accept invitation');
            }

            toast.success('Welcome to the team!');
            navigate('/dashboard');
          }
        } else {
          // Normal signup
          const validation = signUpSchema.safeParse({ email, password, companyName, fullName });
          if (!validation.success) {
            toast.error(validation.error.errors[0].message);
            setLoading(false);
            return;
          }

          const { error } = await signUp(email, password, companyName, fullName);
          if (error) {
            if (error.message.includes('already registered')) {
              toast.error('An account with this email already exists. Please sign in.');
            } else {
              toast.error(error.message);
            }
          } else {
            toast.success('Account created successfully!');
            navigate('/dashboard');
          }
        }
      } else {
        const validation = signInSchema.safeParse({ email, password });
        if (!validation.success) {
          toast.error(validation.error.errors[0].message);
          setLoading(false);
          return;
        }

        const { error } = await signIn(email, password);
        if (error) {
          if (error.message.includes('Invalid login credentials')) {
            toast.error('Invalid email or password');
          } else {
            toast.error(error.message);
          }
        } else {
          navigate('/dashboard');
        }
      }
    } finally {
      setLoading(false);
    }
  };

  if (loadingInvitation) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="animate-pulse text-primary">
          <HardHat className="w-12 h-12" />
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-4 blueprint-grid noise-overlay relative">
      <div className="absolute inset-0 bg-gradient-to-br from-background via-background to-card opacity-90" />
      
      <div className="w-full max-w-md relative z-10">
        {/* Logo */}
        <div className="text-center mb-8 stagger-fade-in" style={{ animationDelay: '0ms' }}>
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-xl bg-primary/10 border border-primary/30 mb-4">
            <HardHat className="w-8 h-8 text-primary" />
          </div>
          <h1 className="text-3xl font-heading text-foreground tracking-tight">
            CONSTRUCT<span className="text-primary">LEDGER</span>
          </h1>
          <p className="text-muted-foreground mt-2">
            The Tactical Profit Engine
          </p>
        </div>

        {/* Invitation Banner */}
        {invitationData && (
          <div className="industrial-card p-4 mb-6 border-primary/50 bg-primary/5 stagger-fade-in" style={{ animationDelay: '50ms' }}>
            <div className="flex items-center gap-3">
              <UserPlus className="w-5 h-5 text-primary flex-shrink-0" />
              <div>
                <p className="font-medium text-sm">You're invited to join</p>
                <p className="text-primary font-heading">{invitationData.company_name}</p>
                <p className="text-xs text-muted-foreground mt-1">
                  Role: {invitationData.role === 'manager' ? 'Manager (full access)' : 'Viewer (read-only)'}
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Auth Card */}
        <div className="industrial-card p-8 stagger-fade-in" style={{ animationDelay: '100ms' }}>
          {showForgotPassword ? (
            <>
              <div className="flex items-center gap-2 mb-6">
                <Mail className="w-5 h-5 text-primary" />
                <h2 className="font-heading text-xl">RESET PASSWORD</h2>
              </div>

              {resetEmailSent ? (
                <div className="text-center py-4">
                  <Mail className="w-12 h-12 text-primary mx-auto mb-4" />
                  <p className="text-muted-foreground mb-4">
                    Check your email for a password reset link. It may take a few minutes to arrive.
                  </p>
                  <Button
                    variant="outline"
                    onClick={() => {
                      setShowForgotPassword(false);
                      setResetEmailSent(false);
                    }}
                    className="w-full"
                  >
                    Back to Sign In
                  </Button>
                </div>
              ) : (
                <form onSubmit={handleForgotPassword} className="space-y-4">
                  <div className="space-y-2">
                    <Label htmlFor="email">Email</Label>
                    <Input
                      id="email"
                      type="email"
                      placeholder="you@company.com"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      className="bg-input border-border"
                      disabled={loading}
                    />
                  </div>

                  <Button
                    type="submit"
                    className="w-full tactile-press font-semibold"
                    disabled={loading}
                  >
                    {loading ? (
                      <Loader2 className="w-4 h-4 animate-spin mr-2" />
                    ) : null}
                    Send Reset Link
                  </Button>

                  <Button
                    type="button"
                    variant="ghost"
                    onClick={() => setShowForgotPassword(false)}
                    className="w-full"
                    disabled={loading}
                  >
                    Back to Sign In
                  </Button>
                </form>
              )}
            </>
          ) : (
            <>
              <div className="flex items-center gap-2 mb-6">
                <Building2 className="w-5 h-5 text-primary" />
                <h2 className="font-heading text-xl">
                  {invitationData ? 'ACCEPT INVITATION' : isSignUp ? 'CREATE ACCOUNT' : 'SIGN IN'}
                </h2>
              </div>

              <form onSubmit={handleSubmit} className="space-y-4">
                {isSignUp && !invitationData && (
                  <>
                    <div className="space-y-2">
                      <Label htmlFor="companyName">Company Name</Label>
                      <Input
                        id="companyName"
                        type="text"
                        placeholder="Acme Construction LLC"
                        value={companyName}
                        onChange={(e) => setCompanyName(e.target.value)}
                        className="bg-input border-border"
                        disabled={loading}
                      />
                    </div>
                  </>
                )}
                
                {isSignUp && (
                  <div className="space-y-2">
                    <Label htmlFor="fullName">Your Full Name</Label>
                    <Input
                      id="fullName"
                      type="text"
                      placeholder="John Smith"
                      value={fullName}
                      onChange={(e) => setFullName(e.target.value)}
                      className="bg-input border-border"
                      disabled={loading}
                    />
                  </div>
                )}

                <div className="space-y-2">
                  <Label htmlFor="email">Email</Label>
                  <Input
                    id="email"
                    type="email"
                    placeholder="you@company.com"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="bg-input border-border"
                    disabled={loading || !!invitationData}
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="password">Password</Label>
                  <Input
                    id="password"
                    type="password"
                    placeholder="••••••••"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    className="bg-input border-border"
                    disabled={loading}
                  />
                  {!isSignUp && (
                    <button
                      type="button"
                      onClick={() => setShowForgotPassword(true)}
                      className="text-sm text-primary hover:underline"
                    >
                      Forgot password?
                    </button>
                  )}
                </div>

                <Button
                  type="submit"
                  className="w-full tactile-press font-semibold"
                  disabled={loading}
                >
                  {loading ? (
                    <Loader2 className="w-4 h-4 animate-spin mr-2" />
                  ) : null}
                  {invitationData ? 'Accept & Join' : isSignUp ? 'Create Account' : 'Sign In'}
                </Button>
              </form>

              {!invitationData && (
                <div className="mt-6 pt-6 border-t border-border text-center">
                  <p className="text-muted-foreground text-sm">
                    {isSignUp ? 'Already have an account?' : "Don't have an account?"}
                    <button
                      type="button"
                      onClick={() => setIsSignUp(!isSignUp)}
                      className="text-primary hover:underline ml-1 font-medium"
                      disabled={loading}
                    >
                      {isSignUp ? 'Sign In' : 'Create one'}
                    </button>
                  </p>
                </div>
              )}
            </>
          )}
        </div>

        {/* Footer */}
        <p className="text-center text-muted-foreground text-xs mt-6 stagger-fade-in" style={{ animationDelay: '200ms' }}>
          No guesswork. Just the granular, project-tied truth of your profit.
        </p>
      </div>
    </div>
  );
}
