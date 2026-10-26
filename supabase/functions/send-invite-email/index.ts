// Emails an invitation (app link and sign-in steps) to a person the association has just invited.
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
    const { email } = await req.json();
    const target = String(email ?? '').trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(target)) return json({ error: 'invalid_email' }, 400);

    const url = Deno.env.get('SUPABASE_URL')!;
    const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    });
    // The directory only lists invitations to members who may manage people, so this also authorises the caller.
    const { data: rows, error } = await asUser.rpc('directory');
    if (error) return json({ error: 'not_allowed' }, 403);
    // deno-lint-ignore no-explicit-any
    const invite = (rows ?? []).find((r: any) => r.kind === 'invited' && String(r.email ?? '').toLowerCase() === target);
    if (!invite) return json({ error: 'no_pending_invite' }, 404);

    const { data: assocId } = await asUser.rpc('my_association');
    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: assoc } = await admin.from('associations').select('name').eq('id', assocId).maybeSingle();
    const name = assoc?.name ?? 'your association';
    const appUrl = Deno.env.get('APP_URL') ?? 'https://flatsphere.pages.dev';
    const role = String(invite.role ?? '').replace(/_/g, ' ');

    const html = `<div style="font-family:Arial,sans-serif"><h2 style="margin:0">${esc(name)}</h2>
      <p>${esc(invite.full_name)}, you have been invited to FlatSphere${role ? ' as <b>' + esc(role) + '</b>' : ''}.</p>
      <ol><li>Open <a href="${esc(appUrl)}">${esc(appUrl)}</a></li>
      <li>Enter this email address (<b>${esc(target)}</b>) and tap Send code</li>
      <li>Enter the 6-digit code that is emailed to you</li></ol>
      <p style="color:#777;font-size:12px">If you were not expecting this invitation, you can ignore this email.</p></div>`;

    const smtp = new SMTPClient({
      connection: {
        hostname: 'smtp.gmail.com', port: 465, tls: true,
        auth: { username: 'noreply.flatsphere@gmail.com', password: Deno.env.get('SMTP_GMAIL_APP_PASSWORD')! },
      },
    });
    await smtp.send({
      from: 'FlatSphere <noreply.flatsphere@gmail.com>', to: target,
      subject: `You are invited to ${name} on FlatSphere`, content: 'auto', html,
    });
    await smtp.close();
    return json({ sent: 1 });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
