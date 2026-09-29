import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await req.json();
    const { cloud_id, households: pushHouseholds, members: pushMembers, vitals: pushVitals } = payload;

    if (!cloud_id) {
      return new Response(
        JSON.stringify({ error: "Missing required field: cloud_id" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
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

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Resolve phc_id: either from payload or from the worker's profile
    let phcId = payload.phc_id;
    if (!phcId) {
      const { data: prof } = await supabase
        .from("profiles")
        .select("phc_id")
        .eq("user_id", cloud_id)
        .maybeSingle();
      if (prof?.phc_id) {
        phcId = prof.phc_id;
      }
    }

    let syncedCount = 0;

    // ── PUSH: Insert/update households, members, vitals from device ──
    if (pushHouseholds && Array.isArray(pushHouseholds) && pushHouseholds.length > 0) {
      const cleanedHouseholds = [];
      for (const h of pushHouseholds) {
        let vId = h.village_id || null;
        let vName = h.village_name || null;
        if (!vId && vName && phcId) {
          const { data: vRecord } = await supabase
            .from("villages")
            .select("id,name,village_or_ward")
            .eq("phc_id", phcId)
            .or(`name.eq."${vName}",village_or_ward.eq."${vName}"`)
            .maybeSingle();
          if (vRecord?.id) {
            vId = vRecord.id;
            vName = vRecord.name || vRecord.village_or_ward || vName;
          }
        }

        cleanedHouseholds.push({
          id: h.cloud_id || crypto.randomUUID(),
          phc_id: phcId,
          asha_id: cloud_id,
          village_id: vId,
          village_name: vName || 'General',
          head_name: h.family_head_name || '',
          house_number: h.house_number || null,
          contact_number: h.contact_number || null,
          deleted_at: h.deleted_at || null,
        });
      }

      const { error: hhError } = await supabase
        .from("households")
        .upsert(cleanedHouseholds, { onConflict: "id" });

      if (hhError) {
        console.error("Household upsert error:", hhError);
      } else {
        syncedCount += cleanedHouseholds.length;
      }
    }

    if (pushMembers && Array.isArray(pushMembers) && pushMembers.length > 0) {
      const cleanedMembers = pushMembers.map((m: any) => ({
        id: m.cloud_id || crypto.randomUUID(),
        household_id: m.household_cloud_id || null,
        phc_id: phcId,
        asha_id: cloud_id,
        full_name: m.full_name || '',
        age: m.age != null ? Number(m.age) : null,
        gender: m.gender || null,
        relation_to_head: m.relationship_to_head || null,
        abha_id: m.abha_id || null,
        mobile_number: m.mobile_number || null,
        is_pregnant: m.is_pregnant === 1 || m.is_pregnant === true,
        pregnancy_risk: (m.is_high_risk_pregnancy === 1 || m.is_high_risk_pregnancy === true) ? 'high' : 'normal',
        lmp_date: m.lmp_date || null,
        edd_date: m.edd_date || null,
        is_high_risk_pregnancy: m.is_high_risk_pregnancy === 1 || m.is_high_risk_pregnancy === true,
        is_lactating: m.is_lactating === 1 || m.is_lactating === true,
        td1_vaccine: m.td1_vaccine === 1 || m.td1_vaccine === true,
        td2_vaccine: m.td2_vaccine === 1 || m.td2_vaccine === true,
        td_booster: m.td_booster === 1 || m.td_booster === true,
        ifa_tablets_given: m.ifa_tablets_given || 0,
        calcium_tablets_given: m.calcium_tablets_given || 0,
        birth_weight: m.birth_weight || null,
        delivery_type: m.delivery_type || null,
        muac_cm: m.muac_cm || null,
        has_chronic_condition: m.has_chronic_condition === 1 || m.has_chronic_condition === true,
        chronic_notes: m.chronic_notes || null,
        deleted_at: m.deleted_at || null,
      }));

      const { error: mError } = await supabase
        .from("members")
        .upsert(cleanedMembers, { onConflict: "id" });

      if (mError) {
        console.error("Members upsert error:", mError);
      } else {
        syncedCount += cleanedMembers.length;
      }
    }

    if (pushVitals && Array.isArray(pushVitals) && pushVitals.length > 0) {
      const cleanedVitals = pushVitals.map((v: any) => ({
        id: v.cloud_id || crypto.randomUUID(),
        member_id: v.member_cloud_id || null,
        phc_id: phcId,
        recorded_by: cloud_id,
        asha_id: cloud_id,
        systolic_bp: v.blood_pressure_systolic || null,
        bp_systolic: v.blood_pressure_systolic || null,
        diastolic_bp: v.blood_pressure_diastolic || null,
        bp_diastolic: v.blood_pressure_diastolic || null,
        temperature: v.temperature || null,
        temperature_c: v.temperature || null,
        pulse: v.pulse_rate || null,
        pulse_rate: v.pulse_rate || null,
        spo2: v.spo2 || null,
        resp_rate: v.respiratory_rate || null,
        respiratory_rate: v.respiratory_rate || null,
        blood_sugar_fasting: v.blood_sugar_fasting || null,
        blood_sugar_postprandial: v.blood_sugar_postprandial || null,
        news2_score: v.news2_score || null,
        sepsis_risk: v.sepsis_risk || null,
        notes: v.notes || null,
        device_id: v.device_id || null,
        recorded_at: v.recorded_at || new Date().toISOString(),
      }));

      const { error: vError } = await supabase
        .from("vitals")
        .upsert(cleanedVitals, { onConflict: "id" });

      if (vError) {
        console.error("Vitals upsert error:", vError);
      } else {
        syncedCount += cleanedVitals.length;
      }
    }

    // ── PULL: Fetch latest data for this worker or worker's PHC ──
    const { data: households, error: hhErr } = await supabase
      .from("households")
      .select("*,village:villages(id,name,village_or_ward,block)")
      .eq("asha_id", cloud_id)
      .is("deleted_at", null);

    const { data: members, error: mErr } = await supabase
      .from("members")
      .select("*")
      .eq("asha_id", cloud_id)
      .is("deleted_at", null);

    const { data: vitals, error: vErr } = await supabase
      .from("vitals")
      .select("*")
      .eq("asha_id", cloud_id);

    // ── Update last_sync_at on profiles ──
    await supabase
      .from("profiles")
      .update({ last_sync_at: new Date().toISOString() })
      .eq("user_id", cloud_id);

    return new Response(
      JSON.stringify({
        success: true,
        pushed: syncedCount,
        households: households ?? [],
        members: members ?? [],
        vitals: vitals ?? [],
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : String(err) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
