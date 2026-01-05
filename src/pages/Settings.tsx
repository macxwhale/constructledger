import { useEffect, useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import {
  ArrowLeft,
  HardHat,
  User,
  Building2,
  Users,
  Loader2,
  Mail,
  Trash2,
  UserPlus,
} from 'lucide-react';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { Badge } from '@/components/ui/badge';
import type { Tables, Enums } from '@/integrations/supabase/types';

type Profile = Tables<'profiles'>;
type UserRole = Tables<'user_roles'>;

interface TeamMember {
  id: string;
  user_id: string;
  full_name: string | null;
  email: string;
  role: Enums<'app_role'>;
}

export default function Settings() {
  const { user, loading: authLoading } = useAuth();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  
  // Profile state
  const [fullName, setFullName] = useState('');
  const [companyName, setCompanyName] = useState('');
  const [companyId, setCompanyId] = useState<string | null>(null);
  
  // Team members state
  const [teamMembers, setTeamMembers] = useState<TeamMember[]>([]);
  const [loadingTeam, setLoadingTeam] = useState(true);
  
  // Invite state
  const [inviteEmail, setInviteEmail] = useState('');
  const [inviting, setInviting] = useState(false);
  
  // Delete state
  const [memberToRemove, setMemberToRemove] = useState<TeamMember | null>(null);
  const [removing, setRemoving] = useState(false);

  useEffect(() => {
    if (!authLoading && !user) {
      navigate('/auth');
    }
  }, [user, authLoading, navigate]);

  useEffect(() => {
    if (user) {
      fetchProfileAndCompany();
      fetchTeamMembers();
    }
  }, [user]);

  const fetchProfileAndCompany = async () => {
    try {
      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('*, companies(id, name)')
        .eq('user_id', user!.id)
        .single();

      if (profileError) throw profileError;

      setFullName(profile.full_name || '');
      if (profile.companies) {
        const company = profile.companies as { id: string; name: string };
        setCompanyName(company.name);
        setCompanyId(company.id);
      }
    } catch (error) {
      toast.error('Failed to load profile');
    } finally {
      setLoading(false);
    }
  };

  const fetchTeamMembers = async () => {
    try {
      // Get company_id first
      const { data: profile } = await supabase
        .from('profiles')
        .select('company_id')
        .eq('user_id', user!.id)
        .single();

      if (!profile?.company_id) return;

      // Get all profiles in the company with their roles
      const { data: profiles, error } = await supabase
        .from('profiles')
        .select('id, user_id, full_name')
        .eq('company_id', profile.company_id);

      if (error) throw error;

      // Get roles for all users
      const { data: roles } = await supabase
        .from('user_roles')
        .select('user_id, role')
        .eq('company_id', profile.company_id);

      // Get user emails from auth (we'll use the profile user_id for now)
      const members: TeamMember[] = (profiles || []).map((p) => {
        const userRole = roles?.find((r) => r.user_id === p.user_id);
        return {
          id: p.id,
          user_id: p.user_id,
          full_name: p.full_name,
          email: '', // We'll get this from auth metadata if available
          role: userRole?.role || 'viewer',
        };
      });

      setTeamMembers(members);
    } catch (error) {
      console.error('Failed to load team members:', error);
    } finally {
      setLoadingTeam(false);
    }
  };

  const handleSaveProfile = async () => {
    setSaving(true);
    try {
      // Update profile
      const { error: profileError } = await supabase
        .from('profiles')
        .update({ full_name: fullName.trim() })
        .eq('user_id', user!.id);

      if (profileError) throw profileError;

      // Update company name
      if (companyId) {
        const { error: companyError } = await supabase
          .from('companies')
          .update({ name: companyName.trim() })
          .eq('id', companyId);

        if (companyError) throw companyError;
      }

      toast.success('Settings saved successfully');
    } catch (error) {
      toast.error('Failed to save settings');
    } finally {
      setSaving(false);
    }
  };

  const handleRemoveMember = async () => {
    if (!memberToRemove || !companyId) return;

    setRemoving(true);
    try {
      // Remove user role
      const { error: roleError } = await supabase
        .from('user_roles')
        .delete()
        .eq('user_id', memberToRemove.user_id)
        .eq('company_id', companyId);

      if (roleError) throw roleError;

      // Remove profile
      const { error: profileError } = await supabase
        .from('profiles')
        .delete()
        .eq('user_id', memberToRemove.user_id)
        .eq('company_id', companyId);

      if (profileError) throw profileError;

      toast.success('Team member removed');
      fetchTeamMembers();
    } catch (error) {
      toast.error('Failed to remove team member');
    } finally {
      setRemoving(false);
      setMemberToRemove(null);
    }
  };

  const getRoleBadgeVariant = (role: Enums<'app_role'>) => {
    switch (role) {
      case 'manager':
        return 'default';
      case 'viewer':
        return 'secondary';
      default:
        return 'outline';
    }
  };

  if (authLoading || loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="animate-pulse text-primary">
          <HardHat className="w-12 h-12" />
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen">
      {/* Header */}
      <header className="border-b border-border bg-card/50 backdrop-blur-sm sticky top-0 z-40">
        <div className="container mx-auto px-4 py-4">
          <Button
            variant="ghost"
            size="sm"
            asChild
            className="text-muted-foreground hover:text-foreground"
          >
            <Link to="/dashboard">
              <ArrowLeft className="w-4 h-4 mr-2" />
              Back to Dashboard
            </Link>
          </Button>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-4 py-8 max-w-3xl">
        <div className="mb-8">
          <h1 className="text-3xl font-heading mb-2">SETTINGS</h1>
          <p className="text-muted-foreground">
            Manage your account and company settings
          </p>
        </div>

        <div className="space-y-6">
          {/* Profile Settings */}
          <Card className="industrial-card">
            <CardHeader>
              <CardTitle className="flex items-center gap-2 font-heading">
                <User className="w-5 h-5" />
                PROFILE
              </CardTitle>
              <CardDescription>
                Your personal account information
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="email">Email</Label>
                <Input
                  id="email"
                  value={user?.email || ''}
                  disabled
                  className="bg-muted"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="fullName">Full Name</Label>
                <Input
                  id="fullName"
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                  placeholder="Your full name"
                />
              </div>
            </CardContent>
          </Card>

          {/* Company Settings */}
          <Card className="industrial-card">
            <CardHeader>
              <CardTitle className="flex items-center gap-2 font-heading">
                <Building2 className="w-5 h-5" />
                COMPANY
              </CardTitle>
              <CardDescription>
                Your company information
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="companyName">Company Name</Label>
                <Input
                  id="companyName"
                  value={companyName}
                  onChange={(e) => setCompanyName(e.target.value)}
                  placeholder="Your company name"
                />
              </div>
            </CardContent>
          </Card>

          {/* Save Button */}
          <Button onClick={handleSaveProfile} disabled={saving} className="w-full">
            {saving && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
            Save Changes
          </Button>

          {/* Team Members */}
          <Card className="industrial-card">
            <CardHeader>
              <CardTitle className="flex items-center gap-2 font-heading">
                <Users className="w-5 h-5" />
                TEAM MEMBERS
              </CardTitle>
              <CardDescription>
                People who have access to your company's projects
              </CardDescription>
            </CardHeader>
            <CardContent>
              {loadingTeam ? (
                <div className="space-y-3">
                  <Skeleton className="h-12 w-full" />
                  <Skeleton className="h-12 w-full" />
                </div>
              ) : teamMembers.length === 0 ? (
                <p className="text-muted-foreground text-center py-4">
                  No team members found
                </p>
              ) : (
                <div className="space-y-3">
                  {teamMembers.map((member) => (
                    <div
                      key={member.id}
                      className="flex items-center justify-between p-3 bg-secondary/30 rounded-lg"
                    >
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
                          <User className="w-5 h-5 text-primary" />
                        </div>
                        <div>
                          <p className="font-medium">
                            {member.full_name || 'Unnamed User'}
                          </p>
                          <p className="text-sm text-muted-foreground">
                            {member.user_id === user?.id ? 'You' : 'Team Member'}
                          </p>
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        <Badge variant={getRoleBadgeVariant(member.role)}>
                          {member.role}
                        </Badge>
                        {member.user_id !== user?.id && (
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-8 w-8 text-destructive hover:text-destructive"
                            onClick={() => setMemberToRemove(member)}
                          >
                            <Trash2 className="w-4 h-4" />
                          </Button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}

              {/* Note about inviting */}
              <div className="mt-6 p-4 bg-muted/50 rounded-lg">
                <p className="text-sm text-muted-foreground">
                  <strong>Note:</strong> To invite new team members, they need to sign up 
                  and be added to your company. Contact support for bulk team setup.
                </p>
              </div>
            </CardContent>
          </Card>
        </div>
      </main>

      {/* Remove Member Dialog */}
      <AlertDialog
        open={!!memberToRemove}
        onOpenChange={() => setMemberToRemove(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove Team Member?</AlertDialogTitle>
            <AlertDialogDescription>
              This will remove {memberToRemove?.full_name || 'this user'} from your 
              company. They will no longer have access to any projects.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={removing}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleRemoveMember}
              disabled={removing}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {removing ? 'Removing...' : 'Remove'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
