!!import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await req.json();
    const {
      worker_name,
      username,
      phone,
      aadhaar_last4 = "0000",
      phc_id,
      village_names = [],
    } = payload;

    const admin_address =
      payload.admin_address ||
      Deno.env.get("ADMIN_WALLET_ADDRESS") ||
      "0xB7a280Cd618dB5a0E82D84306DB423728034A089";

    if (!worker_name || !phone || !username || !phc_id) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields: worker_name, username, phone, or phc_id",
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const relayUrl = Deno.env.get("RELAY_URL");
    const relaySecret = Deno.env.get("RELAY_ADMIN_SECRET");

    if (!relayUrl || !relaySecret) {
      return new Response(
        JSON.stringify({
          error: "RELAY_URL or RELAY_ADMIN_SECRET is not configured in Edge Function secrets.",
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(
        JSON.stringify({
          error: "SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not configured in Edge Function environment.",
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 1. Call Python Relay to generate on-chain wallet & register in WorkerRegistry
    const cleanRelayUrl = relayUrl.replace(/\/+$/, "");
    const relayResponse = await fetch(`${cleanRelayUrl}/register-worker`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Admin-Secret": relaySecret,
      },
      body: JSON.stringify({
        worker_name: worker_name.trim(),
        phone: phone.trim(),
        aadhaar_last4: String(aadhaar_last4).slice(-4) || "0000",
        admin_address: admin_address.trim(),
      }),
    });

    if (!relayResponse.ok) {
      const errText = await relayResponse.text();
      return new Response(
        JSON.stringify({
          error: `Relay error (${relayResponse.status}): ${errText}`,
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const relayData = await relayResponse.json();
    const walletAddress = relayData.worker_address;

    if (!walletAddress || typeof walletAddress !== "string") {
      return new Response(
        JSON.stringify({
          error: `Relay response missing valid worker_address: ${JSON.stringify(relayData)}`,
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. Initialize Supabase Admin client with service role key
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // 3. Resolve Auth User ID (creates an auth.users record if possible)
    let targetUserId: string = crypto.randomUUID();
    const cleanPhone = phone.trim();
    const cleanUsername = username.trim().toLowerCase();
    const syntheticEmail = `${cleanUsername}@asha.healthvault.local`;

    try {
      const { data: authData, error: authError } = await supabase.auth.admin.createUser({
        email: syntheticEmail,
        password: `Asha@${String(aadhaar_last4).slice(-4) || "2026"}!`,
        email_confirm: true,
        phone_confirm: true,
        user_metadata: {
          full_name: worker_name.trim(),
          role: "asha",
          username: cleanUsername,
        },
      });

      if (authData?.user?.id) {
        targetUserId = authData.user.id;
      } else if (authError) {
        console.warn("Auth user creation skipped:", authError.message);
        // If auth user already exists or failed, check for existing profile
        const { data: existingProfile } = await supabase
          .from("profiles")
          .select("user_id")
          .or(`phone.eq.${cleanPhone},username.eq.${cleanUsername}`)
          .maybeSingle();

        if (existingProfile?.user_id) {
          targetUserId = existingProfile.user_id;
        }
      }
    } catch (authEx) {
      console.warn("Auth admin createUser exception:", authEx);
    }

    // 4. Create or update profile in Supabase profiles table
    const profilePayload: Record<string, any> = {
      user_id: targetUserId,
      phc_id,
      role: "asha",
      full_name: worker_name.trim(),
      username: cleanUsername,
      phone: cleanPhone,
      wallet_address: walletAddress,
      is_active: true,
      updated_at: new Date().toISOString(),
    };

    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .upsert(profilePayload, { onConflict: "user_id" })
      .select()
      .single();

    if (profileError) {
      // In case username column or user_id had a schema mismatch, attempt insert with core fields
      console.error("Profile upsert error:", profileError);
      return new Response(
        JSON.stringify({
          error: `Supabase profile save error: ${profileError.message}. Please ensure migration 0003_worker_provisioning.sql has been run.`,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const userId = profile?.user_id || targetUserId;

    // 5. Link villages if provided and profile_villages table exists
    if (village_names && Array.isArray(village_names) && village_names.length > 0) {
      try {
        const { data: insertedVillages } = await supabase
          .from("villages")
          .upsert(
            village_names.map((name: string) => ({
              phc_id,
              name: name.trim(),
              village_or_ward: name.trim(),
            })),
            { onConflict: "phc_id,name", ignoreDuplicates: true }
          )
          .select("id");

        if (insertedVillages && insertedVillages.length > 0) {
          await supabase.from("profile_villages").upsert(
            insertedVillages.map((v: { id: string }) => ({
              user_id: userId,
              village_id: v.id,
            })),
            { onConflict: "user_id,village_id", ignoreDuplicates: true }
          );
        }
      } catch (vErr) {
        console.warn("Village link skipped (non-critical):", vErr);
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        worker: {
          id: userId,
          full_name: profile.full_name,
          username: profile.username || cleanUsername,
          phone: profile.phone,
          wallet_address: walletAddress,
          tx_hash: relayData.tx_hash,
          explorer: relayData.explorer || `https://testnet.mstscan.com/address/${walletAddress}`,
        },
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: any) {
    console.error("Unhandled error in provision-worker:", err);
    return new Response(
      JSON.stringify({ error: err.message || "Internal provision-worker error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
