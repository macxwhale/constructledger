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
  Send,
  Clock,
  X,
  Briefcase,
  Plus,
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import type { Tables, Enums } from '@/integrations/supabase/types';

interface TeamMember {
  id: string;
  user_id: string;
  full_name: string | null;
  email: string;
  role: Enums<'app_role'>;
}

interface PendingInvitation {
  id: string;
  email: string;
  role: Enums<'app_role'>;
  expires_at: string;
  created_at: string;
}

export default function Settings() {
  const { user, loading: authLoading } = useAuth();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [isManager, setIsManager] = useState(false);
  
  // Profile state
  const [fullName, setFullName] = useState('');
  const [companyName, setCompanyName] = useState('');
  const [companyId, setCompanyId] = useState<string | null>(null);
  
  // Team members state
  const [teamMembers, setTeamMembers] = useState<TeamMember[]>([]);
  const [pendingInvitations, setPendingInvitations] = useState<PendingInvitation[]>([]);
  const [loadingTeam, setLoadingTeam] = useState(true);
  
  // Invite state
  const [inviteEmail, setInviteEmail] = useState('');
  const [inviteRole, setInviteRole] = useState<'manager' | 'viewer'>('viewer');
  const [inviting, setInviting] = useState(false);
  
  // Delete state
  const [memberToRemove, setMemberToRemove] = useState<TeamMember | null>(null);
  const [invitationToCancel, setInvitationToCancel] = useState<PendingInvitation | null>(null);
  const [removing, setRemoving] = useState(false);

  // Departments state
  const [departments, setDepartments] = useState<Tables<'departments'>[]>([]);
  const [newDepartmentName, setNewDepartmentName] = useState('');
  const [loadingDepartments, setLoadingDepartments] = useState(true);
  const [addingDepartment, setAddingDepartment] = useState(false);
  const [departmentToDelete, setDepartmentToDelete] = useState<Tables<'departments'> | null>(null);

  useEffect(() => {
    if (!authLoading && !user) {
      navigate('/auth');
    }
  }, [user, authLoading, navigate]);

  useEffect(() => {
    if (user) {
      fetchProfileAndCompany();
      fetchTeamMembers();
      fetchPendingInvitations();
      fetchDepartments();
      checkIfManager();
    }
  }, [user]);

  const checkIfManager = async () => {
    // Get user's company first, then check role within that company
    const { data: profile } = await supabase
      .from('profiles')
      .select('company_id')
      .eq('user_id', user!.id)
      .single();

    if (!profile?.company_id) {
      setIsManager(false);
      return;
    }

    const { data } = await supabase
      .from('user_roles')
      .select('role')
      .eq('user_id', user!.id)
      .eq('company_id', profile.company_id)
      .single();
    
    setIsManager(data?.role === 'manager');
  };

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

  const fetchPendingInvitations = async () => {
    try {
      // Get user's company first
      const { data: profile } = await supabase
        .from('profiles')
        .select('company_id')
        .eq('user_id', user!.id)
        .single();

      if (!profile?.company_id) return;

      // Fetch pending invitations for this company (RLS ensures manager access)
      const { data, error } = await (supabase as any)
        .from('invitations')
        .select('id, email, role, expires_at, created_at')
        .eq('company_id', profile.company_id)
        .is('accepted_at', null)
        .gt('expires_at', new Date().toISOString())
        .order('created_at', { ascending: false });

      if (error) {
        console.error('Failed to load invitations:', error);
        toast.error('Failed to load pending invitations');
        return;
      }

      setPendingInvitations((data as PendingInvitation[]) || []);
    } catch (error) {
      console.error('Failed to load invitations:', error);
      toast.error('Failed to load pending invitations');
    }
  };

  const fetchDepartments = async () => {
    try {
      const { data: profile } = await supabase
        .from('profiles')
        .select('company_id')
        .eq('user_id', user!.id)
        .single();

      if (!profile?.company_id) return;

      const { data, error } = await supabase
        .from('departments')
        .select('*')
        .eq('company_id', profile.company_id)
        .order('name');

      if (error) throw error;
      setDepartments(data || []);
    } catch (error) {
      console.error('Failed to load departments:', error);
    } finally {
      setLoadingDepartments(false);
    }
  };

  const handleAddDepartment = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newDepartmentName.trim() || !companyId) return;

    setAddingDepartment(true);
    try {
      const { data, error } = await supabase
        .from('departments')
        .insert({
          company_id: companyId,
          name: newDepartmentName.trim(),
        })
        .select()
        .single();

      if (error) throw error;

      toast.success('Department added successfully');
      setNewDepartmentName('');
      setDepartments((prev) => [...prev, data].sort((a, b) => a.name.localeCompare(b.name)));
    } catch (error: any) {
      if (error.code === '23505') {
        toast.error('A department with this name already exists');
      } else {
        toast.error('Failed to add department');
      }
    } finally {
      setAddingDepartment(false);
    }
  };

  const handleDeleteDepartment = async () => {
    if (!departmentToDelete) return;

    setRemoving(true);
    try {
      const { error } = await supabase
        .from('departments')
        .delete()
        .eq('id', departmentToDelete.id);

      if (error) throw error;

      toast.success('Department deleted successfully');
      setDepartments((prev) => prev.filter((d) => d.id !== departmentToDelete.id));
    } catch (error) {
      toast.error('Failed to delete department');
    } finally {
      setRemoving(false);
      setDepartmentToDelete(null);
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

  const handleInviteMember = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!inviteEmail.trim()) return;

    setInviting(true);
    try {
      const { data, error } = await supabase.functions.invoke('send-invitation', {
        body: {
          email: inviteEmail.trim().toLowerCase(),
          role: inviteRole,
          appUrl: window.location.origin,
        },
      });

      if (error) throw error;
      if (data?.error) throw new Error(data.error);

      toast.success(`Invitation sent to ${inviteEmail}`);
      setInviteEmail('');
      setInviteRole('viewer');
      fetchPendingInvitations();
    } catch (error: any) {
      toast.error(error.message || 'Failed to send invitation');
    } finally {
      setInviting(false);
    }
  };

  const handleCancelInvitation = async () => {
    if (!invitationToCancel) return;

    setRemoving(true);
    try {
      // Use raw query since types haven't been regenerated for invitations table yet
      const { error } = await (supabase as any)
        .from('invitations')
        .delete()
        .eq('id', invitationToCancel.id);

      if (error) throw error;

      toast.success('Invitation cancelled');
      fetchPendingInvitations();
    } catch (error) {
      toast.error('Failed to cancel invitation');
    } finally {
      setRemoving(false);
      setInvitationToCancel(null);
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

  const formatTimeRemaining = (expiresAt: string) => {
    const expires = new Date(expiresAt);
    const now = new Date();
    const daysRemaining = Math.ceil((expires.getTime() - now.getTime()) / (1000 * 60 * 60 * 24));
    return `${daysRemaining} day${daysRemaining !== 1 ? 's' : ''} left`;
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
                  disabled={!isManager}
                />
                {!isManager && (
                  <p className="text-xs text-muted-foreground">
                    Only managers can edit the company name
                  </p>
                )}
              </div>
            </CardContent>
          </Card>

          {/* Save Button */}
          <Button onClick={handleSaveProfile} disabled={saving} className="w-full">
            {saving && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
            Save Changes
          </Button>

          {/* Department Management */}
          <Card className="industrial-card">
            <CardHeader>
              <CardTitle className="flex items-center gap-2 font-heading">
                <Briefcase className="w-5 h-5" />
                DEPARTMENTS
              </CardTitle>
              <CardDescription>
                Categorize your costs by construction phase or department
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
              {isManager && (
                <form onSubmit={handleAddDepartment} className="flex gap-2">
                  <Input
                    placeholder="e.g., Electrical, Plumbing"
                    value={newDepartmentName}
                    onChange={(e) => setNewDepartmentName(e.target.value)}
                    disabled={addingDepartment}
                  />
                  <Button type="submit" disabled={addingDepartment || !newDepartmentName.trim()}>
                    {addingDepartment ? (
                      <Loader2 className="w-4 h-4 animate-spin" />
                    ) : (
                      <Plus className="w-4 h-4 mr-2" />
                    )}
                    Add
                  </Button>
                </form>
              )}

              <div className="space-y-2">
                {loadingDepartments ? (
                  <div className="space-y-2">
                    <Skeleton className="h-10 w-full" />
                    <Skeleton className="h-10 w-full" />
                  </div>
                ) : departments.length === 0 ? (
                  <p className="text-sm text-muted-foreground text-center py-4">
                    No departments added yet
                  </p>
                ) : (
                  <div className="grid gap-2">
                    {departments.map((dept) => (
                      <div
                        key={dept.id}
                        className="flex items-center justify-between p-3 bg-secondary/30 rounded-lg group"
                      >
                        <span className="font-medium">{dept.name}</span>
                        {isManager && (
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-8 w-8 text-destructive opacity-0 group-hover:opacity-100 transition-opacity"
                            onClick={() => setDepartmentToDelete(dept)}
                          >
                            <Trash2 className="w-4 h-4" />
                          </Button>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </CardContent>
          </Card>

          {/* Invite Team Members (Managers only) */}
          {isManager && (
            <Card className="industrial-card">
              <CardHeader>
                <CardTitle className="flex items-center gap-2 font-heading">
                  <UserPlus className="w-5 h-5" />
                  INVITE TEAM MEMBER
                </CardTitle>
                <CardDescription>
                  Send an invitation to add someone to your company
                </CardDescription>
              </CardHeader>
              <CardContent>
                <form onSubmit={handleInviteMember} className="space-y-4">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div className="space-y-2">
                      <Label htmlFor="inviteEmail">Email Address</Label>
                      <Input
                        id="inviteEmail"
                        type="email"
                        placeholder="colleague@company.com"
                        value={inviteEmail}
                        onChange={(e) => setInviteEmail(e.target.value)}
                        disabled={inviting}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="inviteRole">Role</Label>
                      <Select
                        value={inviteRole}
                        onValueChange={(value: 'manager' | 'viewer') => setInviteRole(value)}
                        disabled={inviting}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="Select role" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="manager">Manager (full access)</SelectItem>
                          <SelectItem value="viewer">Viewer (read-only)</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                  <Button type="submit" disabled={inviting || !inviteEmail.trim()} className="w-full md:w-auto">
                    {inviting ? (
                      <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                    ) : (
                      <Send className="w-4 h-4 mr-2" />
                    )}
                    Send Invitation
                  </Button>
                </form>

                {/* Pending Invitations */}
                {pendingInvitations.length > 0 && (
                  <div className="mt-6 pt-6 border-t border-border">
                    <h4 className="font-medium mb-3 flex items-center gap-2">
                      <Clock className="w-4 h-4" />
                      Pending Invitations
                    </h4>
                    <div className="space-y-2">
                      {pendingInvitations.map((invite) => (
                        <div
                          key={invite.id}
                          className="flex items-center justify-between p-3 bg-secondary/30 rounded-lg"
                        >
                          <div className="flex items-center gap-3">
                            <Mail className="w-4 h-4 text-muted-foreground" />
                            <div>
                              <p className="text-sm font-medium">{invite.email}</p>
                              <p className="text-xs text-muted-foreground">
                                {formatTimeRemaining(invite.expires_at)}
                              </p>
                            </div>
                          </div>
                          <div className="flex items-center gap-2">
                            <Badge variant={getRoleBadgeVariant(invite.role)}>
                              {invite.role}
                            </Badge>
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-destructive hover:text-destructive"
                              onClick={() => setInvitationToCancel(invite)}
                            >
                              <X className="w-4 h-4" />
                            </Button>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </CardContent>
            </Card>
          )}

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
                        {member.user_id !== user?.id && isManager && (
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
            </CardContent>
          </Card>
        </div>
      </main>

      {/* Cancel Invitation Dialog */}
      <AlertDialog
        open={!!invitationToCancel}
        onOpenChange={() => setInvitationToCancel(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Cancel Invitation?</AlertDialogTitle>
            <AlertDialogDescription>
              This will cancel the invitation sent to {invitationToCancel?.email}. 
              They will no longer be able to join using this link.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={removing}>Keep Invitation</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleCancelInvitation}
              disabled={removing}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {removing ? 'Cancelling...' : 'Cancel Invitation'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

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

      {/* Delete Department Dialog */}
      <AlertDialog
        open={!!departmentToDelete}
        onOpenChange={() => setDepartmentToDelete(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete Department?</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete the "{departmentToDelete?.name}" department? 
              This will remove the association from any existing costs, but will not delete the costs themselves.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={removing}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDeleteDepartment}
              disabled={removing}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {removing ? 'Deleting...' : 'Delete'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
