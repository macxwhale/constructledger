import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.89.0";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface InvitationRequest {
  email: string;
  role: "manager" | "viewer";
  appUrl: string;
}

const handler = async (req: Request): Promise<Response> => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Get auth user from request
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      throw new Error("No authorization header");
    }

    // Create Supabase client with user's auth
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // Get the current user
    const { data: { user }, error: userError } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", "")
    );

    if (userError || !user) {
      throw new Error("Unauthorized");
    }

    // Parse request body
    const { email, role, appUrl }: InvitationRequest = await req.json();

    if (!email || !role || !appUrl) {
      throw new Error("Missing required fields: email, role, appUrl");
    }

    console.log(`Processing invitation for ${email} with role ${role}`);

    // Get user's company
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("company_id")
      .eq("user_id", user.id)
      .single();

    if (profileError || !profile) {
      console.error("Profile error:", profileError);
      throw new Error("Could not find user profile");
    }

    // Get company name
    const { data: companyData } = await supabase
      .from("companies")
      .select("name")
      .eq("id", profile.company_id)
      .single();

    // Check if user is a manager
    const { data: roleData, error: roleError } = await supabase
      .from("user_roles")
      .select("role")
      .eq("user_id", user.id)
      .eq("company_id", profile.company_id)
      .single();

    if (roleError || roleData?.role !== "manager") {
      throw new Error("Only managers can invite team members");
    }

    // Check if email is already invited (pending)
    const { data: existingInvite } = await supabase
      .from("invitations")
      .select("id")
      .eq("company_id", profile.company_id)
      .eq("email", email.toLowerCase())
      .is("accepted_at", null)
      .gt("expires_at", new Date().toISOString())
      .single();

    if (existingInvite) {
      throw new Error("This email already has a pending invitation");
    }

    // Create invitation
    const { data: invitation, error: inviteError } = await supabase
      .from("invitations")
      .insert({
        company_id: profile.company_id,
        email: email.toLowerCase(),
        role,
        invited_by: user.id,
      })
      .select("token")
      .single();

    if (inviteError) {
      console.error("Invitation error:", inviteError);
      throw new Error("Failed to create invitation");
    }

    // Get company name
    const companyName = companyData?.name || "the company";

    // Get inviter's name
    const { data: inviterProfile } = await supabase
      .from("profiles")
      .select("full_name")
      .eq("user_id", user.id)
      .single();

    const inviterName = inviterProfile?.full_name || "A team member";
    const roleDisplay = role === "manager" ? "Manager (full access)" : "Viewer (read-only)";

    // Send invitation email
    const inviteUrl = `${appUrl}/auth?invite=${invitation.token}`;

    const emailResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify({
        from: "ConstructLedger <no-reply@bunisystems.com>",
        to: [email],
        subject: `You're invited to join ${companyName} on ConstructLedger`,
        html: `
          <!DOCTYPE html>
          <html>
            <head>
              <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
                .container { max-width: 600px; margin: 0 auto; padding: 40px 20px; }
                .header { text-align: center; margin-bottom: 40px; }
                .logo { font-size: 24px; font-weight: bold; color: #f59e0b; }
                .card { background: #1c1c1c; color: #fff; padding: 30px; border-radius: 12px; border: 1px solid #333; }
                .button { display: inline-block; background: #f59e0b; color: #000; padding: 14px 28px; border-radius: 8px; text-decoration: none; font-weight: bold; margin: 20px 0; }
                .footer { text-align: center; margin-top: 40px; color: #888; font-size: 14px; }
                .role-badge { display: inline-block; background: #333; padding: 6px 12px; border-radius: 4px; font-size: 14px; margin: 10px 0; }
              </style>
            </head>
            <body>
              <div class="container">
                <div class="header">
                  <div class="logo">CONSTRUCT<span style="color: #f59e0b;">LEDGER</span></div>
                </div>
                <div class="card">
                  <h2 style="margin-top: 0;">You're Invited! 🎉</h2>
                  <p>${inviterName} has invited you to join <strong>${companyName}</strong> on ConstructLedger.</p>
                  <p>Your role: <span class="role-badge">${roleDisplay}</span></p>
                  <p>Click the button below to accept the invitation and ${role === "manager" ? "start managing projects" : "view project progress"}:</p>
                  <div style="text-align: center;">
                    <a href="${inviteUrl}" class="button">Accept Invitation</a>
                  </div>
                  <p style="color: #888; font-size: 14px;">This invitation will expire in 7 days.</p>
                </div>
                <div class="footer">
                  <p>If you didn't expect this invitation, you can ignore this email.</p>
                </div>
              </div>
            </body>
          </html>
        `,
      }),
    });

    if (!emailResponse.ok) {
      const errorData = await emailResponse.json();
      console.error("Resend API error:", errorData);
      throw new Error("Failed to send invitation email");
    }

    console.log("Email sent successfully:", emailResponse);

    return new Response(
      JSON.stringify({ success: true, message: "Invitation sent successfully" }),
      {
        status: 200,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      }
    );
  } catch (error: any) {
    console.error("Error in send-invitation function:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        status: 400,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      }
    );
  }
};

serve(handler);
