import { createClient } from "@supabase/supabase-js";
import { Resend } from "resend";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { username } = await req.json();

    if (!username) {
      throw new Error("Username is required");
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const resendApiKey = Deno.env.get("RESEND_API_KEY");

    if (!resendApiKey) {
      throw new Error("RESEND_API_KEY is not set");
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const resend = new Resend(resendApiKey);

    // 1. Find the employee
    const { data: employee, error: findError } = await supabase
      .from("employees")
      .select("*")
      .eq("username", username)
      .maybeSingle();

    if (findError) throw findError;
    if (!employee) throw new Error("User not found");
    if (!employee.email) throw new Error("User has no email address linked");

    // 2. Generate Temporary Password
    const tempPassword = Math.random().toString(36).slice(-8);

    // 3. Hash the password (SHA-256)
    const msgBuffer = new TextEncoder().encode(tempPassword);
    const hashBuffer = await crypto.subtle.digest("SHA-256", msgBuffer);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const passwordHash = hashArray
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    // 4. Update Database
    const { error: updateError } = await supabase
      .from("employees")
      .update({ password_hash: passwordHash })
      .eq("id", employee.id);

    if (updateError) throw updateError;

    // 5. Send Email via Resend SDK
    const { data, error } = await resend.emails.send({
      from: "Lucasa POS <onboarding@resend.dev>",
      to: [employee.email],
      subject: "Password Reset Request",
      html: `
        <h1>Password Reset</h1>
        <p>Hello ${employee.first_name},</p>
        <p>Your password has been reset successfully.</p>
        <p><strong>Temporary Password:</strong> ${tempPassword}</p>
        <p>Please log in and change your password immediately.</p>
        <br/>
        <p>Regards,<br/>Lucasa POS Team</p>
      `,
    });

    if (error) {
      console.error("Resend Error:", error);
      throw new Error(`Failed to send email: ${error.message}`);
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: `Password reset sent to ${employee.email}`,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        success: false,
        message: error.message,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});
