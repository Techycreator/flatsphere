// Emails a payment receipt to the flat's owners from the association's Gmail sender.
// Called by the app after the Treasurer records a payment (and later by the Razorpay webhook).
import { createClient } from 'npm:@supabase/supabase-js@2';
import { SMTPClient } from 'https://deno.land/x/denomailer@1.6.0/mod.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
const esc = (s: unknown) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!));

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const { receipt_no } = await req.json();
    const url = Deno.env.get('SUPABASE_URL')!;
    const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    });
    const { data: p } = await asUser
      .from('payments')
      .select('association_id, flat_id, amount, paid_on, mode, reference, receipt_no, flats(number), dues(head)')
      .eq('receipt_no', receipt_no)
      .maybeSingle();
    if (!p) return json({ error: 'not_found' }, 404);
    const { data: allowed } = await asUser.rpc('fin_recorder', { assoc: p.association_id });
    if (!allowed) return json({ error: 'not_allowed' }, 403);

    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: owners } = await admin
      .from('memberships')
      .select('profiles(email)')
      .eq('flat_id', p.flat_id)
      .eq('role', 'owner')
      .is('ended_at', null);
    const { data: assoc } = await admin.from('associations').select('name').eq('id', p.association_id).maybeSingle();
    // deno-lint-ignore no-explicit-any
    const to = [...new Set((owners ?? []).map((o: any) => o.profiles?.email).filter((e: string) => e && !e.endsWith('.invalid')))];
    if (!to.length) return json({ sent: 0 });

    const name = assoc?.name ?? 'Your association';
    // deno-lint-ignore no-explicit-any
    const flat = (p as any).flats?.number ?? '';
    // deno-lint-ignore no-explicit-any
    const head = (p as any).dues?.head ?? 'Advance / other';
    const rows = [
      ['Receipt no.', p.receipt_no], ['Date', p.paid_on], ['Flat', flat], ['Towards', head],
      ['Amount', '₹' + Number(p.amount).toLocaleString('en-IN')], ['Mode', p.mode], ['Reference', p.reference ?? '—'],
    ].map(([k, v]) => `<tr><td style="padding:4px 12px 4px 0;color:#555">${esc(k)}</td><td><b>${esc(v)}</b></td></tr>`).join('');
    const html = `<div style="font-family:Arial,sans-serif"><h2 style="margin:0">${esc(name)}</h2><p>Payment receipt</p>
      <table>${rows}</table><p style="color:#777;font-size:12px">You can download this receipt as a PDF from My dues in FlatSphere.
      Computer-generated receipt; no signature required.</p></div>`;

    const smtp = new SMTPClient({
      connection: {
        hostname: 'smtp.gmail.com', port: 465, tls: true,
        auth: { username: 'noreply.flatsphere@gmail.com', password: Deno.env.get('SMTP_GMAIL_APP_PASSWORD')! },
      },
    });
    await smtp.send({
      from: 'FlatSphere <noreply.flatsphere@gmail.com>', to, subject: `Receipt ${p.receipt_no} – ${name}`,
      content: 'auto', html,
    });
    await smtp.close();
    return json({ sent: to.length });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
