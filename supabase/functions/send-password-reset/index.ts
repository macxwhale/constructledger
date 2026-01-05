import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const resendApiKey = Deno.env.get("RESEND_API_KEY");
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface PasswordResetRequest {
  email: string;
  appUrl: string;
}

const handler = async (req: Request): Promise<Response> => {
  console.log("send-password-reset function invoked");

  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { email, appUrl }: PasswordResetRequest = await req.json();
    console.log("Password reset requested for email:", email);

    if (!email || !appUrl) {
      return new Response(
        JSON.stringify({ error: "Email and appUrl are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Create Supabase client with service role
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Look up user by email using admin API
    const { data: userData, error: userError } = await supabase.auth.admin.listUsers();
    
    if (userError) {
      console.error("Error listing users:", userError);
      // Always return success to prevent email enumeration
      return new Response(
        JSON.stringify({ success: true, message: "If an account exists, a reset link has been sent." }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const user = userData.users.find(u => u.email?.toLowerCase() === email.toLowerCase());

    if (!user) {
      console.log("No user found with email:", email);
      // Always return success to prevent email enumeration
      return new Response(
        JSON.stringify({ success: true, message: "If an account exists, a reset link has been sent." }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log("User found, creating reset token");

    // Delete any existing unused tokens for this email
    await supabase
      .from("password_reset_tokens")
      .delete()
      .eq("email", email.toLowerCase())
      .is("used_at", null);

    // Create new reset token
    const { data: tokenData, error: tokenError } = await supabase
      .from("password_reset_tokens")
      .insert({
        email: email.toLowerCase(),
      })
      .select("token")
      .single();

    if (tokenError) {
      console.error("Error creating reset token:", tokenError);
      throw new Error("Failed to create reset token");
    }

    const resetUrl = `${appUrl}/reset-password?token=${tokenData.token}`;
    console.log("Reset URL generated:", resetUrl);

    // Send email via Resend REST API
    const emailResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "ConstructLedger <no-reply@bunisystems.com>",
        to: [email],
        subject: "Reset Your Password - ConstructLedger",
        html: `
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
          </head>
          <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
            <div style="background: linear-gradient(135deg, #1a1a1a 0%, #2d2d2d 100%); padding: 30px; border-radius: 12px; margin-bottom: 20px;">
              <h1 style="color: #f59e0b; margin: 0; font-size: 24px;">🔐 Password Reset Request</h1>
            </div>
            
            <div style="background: #f8f9fa; padding: 25px; border-radius: 12px; border: 1px solid #e9ecef;">
              <p style="margin-top: 0;">Hello,</p>
              <p>We received a request to reset the password for your ConstructLedger account.</p>
              <p>Click the button below to set a new password:</p>
              
              <div style="text-align: center; margin: 30px 0;">
                <a href="${resetUrl}" style="display: inline-block; background: #f59e0b; color: #000; text-decoration: none; padding: 14px 32px; border-radius: 8px; font-weight: 600; font-size: 16px;">Reset Password</a>
              </div>
              
              <p style="font-size: 14px; color: #666;">This link will expire in 1 hour for security reasons.</p>
              <p style="font-size: 14px; color: #666;">If you didn't request this password reset, you can safely ignore this email.</p>
              
              <hr style="border: none; border-top: 1px solid #e9ecef; margin: 25px 0;">
              
              <p style="font-size: 12px; color: #999; margin-bottom: 0;">
                If the button doesn't work, copy and paste this link into your browser:<br>
                <a href="${resetUrl}" style="color: #f59e0b; word-break: break-all;">${resetUrl}</a>
              </p>
            </div>
            
            <p style="text-align: center; font-size: 12px; color: #999; margin-top: 20px;">
              © ${new Date().getFullYear()} ConstructLedger. All rights reserved.
            </p>
          </body>
          </html>
        `,
      }),
    });

    const emailResult = await emailResponse.json();
    console.log("Email sent result:", emailResult);

    if (!emailResponse.ok) {
      console.error("Failed to send email:", emailResult);
      throw new Error(emailResult.message || "Failed to send email");
    }

    return new Response(
      JSON.stringify({ success: true, message: "If an account exists, a reset link has been sent." }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    console.error("Error in send-password-reset:", error);
    return new Response(
      JSON.stringify({ error: error.message || "Failed to process request" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
};

serve(handler);
