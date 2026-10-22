"""Load or remove sample complaints/approvals on the live DB:
  python3 supabase/sample/sample_data.py seed supabase/sample/sample_data.json
  python3 supabase/sample/sample_data.py cleanup
Needs SUPABASE_URL and SUPABASE_DB_PASSWORD. Sample rows belong to placeholder users @sample.flatsphere.invalid (cannot log in)."""
import json, os, subprocess, sys, urllib.parse

ASSOC = '00000000-0000-0000-0000-000000000001'
DOMAIN = 'sample.flatsphere.invalid'
SAMPLE = [
    ('Rajesh Menon', [('president', None)]),
    ('Anitha Nair', [('secretary', None)]),
    ('Thomas Kurian', [('treasurer', None)]),
    ('Lakshmi Pillai', [('ec_member', None), ('monitor', None)]),
    ('Priya Varghese', [('owner', 'C-204'), ('owner', 'B-205')]),
    ('Arun Das', [('resident', 'C-302')]),
    ('Suresh Kumar', [('caretaker', None)]),
    ('George Antony', [('vice_president', None), ('owner', 'C-302')]),
    ('Deepa Krishnan', [('joint_secretary', None), ('owner', 'C-401')]),
    ('Sanjay Gupta', [('joint_treasurer', None), ('owner', 'A-204')]),
    ('CA Meera Iyer', [('auditor', None)]),
]

def q(v):
    if v is None: return 'null'
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, (int, float)): return str(v)
    return "'" + str(v).replace("'", "''") + "'"

def email(name): return name.replace('CA ', '').split()[0].lower() + '@' + DOMAIN

def resolve(name, default='Suresh Kumar'):
    n = (name or '').split(' (')[0].split(' &')[0].split(' / ')[0].strip()
    for s, _ in SAMPLE:
        if s == n or s.replace('CA ', '') == n: return s
    return default

def pid(name): return f"(select id from profiles where email = {q(email(name))})"
def flat(num): return f"(select id from flats where association_id = '{ASSOC}' and number = {q(num)})"

CLEANUP = f"""
delete from audit_log where actor in (select id from profiles where email like '%@{DOMAIN}')
  or entity_id in (select id::text from approval_requests where initiator in (select id from profiles where email like '%@{DOMAIN}'));
delete from approval_requests where initiator in (select id from profiles where email like '%@{DOMAIN}');
delete from complaint_remarks where complaint_id in (select id from complaints where raised_by in (select id from profiles where email like '%@{DOMAIN}'));
delete from complaints where raised_by in (select id from profiles where email like '%@{DOMAIN}');
delete from expenses where entered_by in (select id from profiles where email like '%@{DOMAIN}');
update expenses set verified_by = null where verified_by in (select id from profiles where email like '%@{DOMAIN}');
update expenses set approved_by = null where approved_by in (select id from profiles where email like '%@{DOMAIN}');
delete from invites where email like '%@{DOMAIN}';
delete from auth.users where email like '%@{DOMAIN}';
"""

def expenses_sql():
    rows = [
        (1, 'Common electricity', 'KSEB', 'Common area bill - Sep', 18640, 'awaiting_treasurer', None, None, False, None),
        (2, 'STP maintenance', 'AquaTech Services', 'Blower motor rewinding', 12500, 'awaiting_treasurer', None, None, False, None),
        (3, 'Cleaning liquids & equipment', 'Kochi Hygiene Mart', 'Phenyl, mops, garbage bags', 3420, 'awaiting_president', 'Thomas Kurian', None, False, None),
        (4, 'Garden', 'Green Thumb Landscaping', 'Monthly garden upkeep', 6000, 'sent_back', None, None, False, 'GST invoice missing - please attach'),
        (5, 'Water bill', 'Kerala Water Authority', 'Bi-monthly water charges', 9870, 'approved', 'Thomas Kurian', 'Rajesh Menon', False, None),
        (8, 'Motor maintenance', 'Sree Electricals', 'Pump 2 bearing replacement', 4800, 'approved', 'Thomas Kurian', 'Rajesh Menon', True, 'Same repair done in July - discuss in EC'),
    ]
    return '\n'.join(
        "insert into expenses (association_id, spent_on, category, vendor, description, amount, status, entered_by, "
        "entered_by_name, verified_by, approved_by, flagged, comment) values "
        f"('{ASSOC}', current_date - {d}, {q(c)}, {q(v)}, {q(desc)}, {amt}, {q(st)}, {pid('Anitha Nair')}, 'Anitha Nair', "
        f"{pid(ver) if ver else 'null'}, {pid(app) if app else 'null'}, {q(fl)}, {q(com)});"
        for d, c, v, desc, amt, st, ver, app, fl, com in rows)

def seed_sql(d):
    out = ['begin;', CLEANUP]
    for name, roles in SAMPLE:
        for role, f in roles:
            des = "array['Membership desk']" if role == 'ec_member' else "'{}'"
            out.append(f"insert into invites (association_id, email, full_name, role, flat_id, designations) values "
                       f"('{ASSOC}', {q(email(name))}, {q(name)}, '{role}', {flat(f) if f else 'null'}, {des});")
        out.append("insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values "
                   f"(gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', {q(email(name))}, now(), now());")
    out.append(f"update memberships set monitor_categories = array['Security','Garden'], monitor_from = '2026-07-01', "
               f"monitor_until = '2026-11-10', assigned_by = 'Rajesh Menon (President)' where role = 'monitor' "
               f"and user_id = {pid('Lakshmi Pillai')};")
    out.append(expenses_sql())
    for c in d['complaints']:
        cols = ['association_id', 'ref', 'flat_id', 'flat_number', 'ticket_type', 'kind', 'category', 'title', 'description',
                'location', 'criticality', 'ai_suggested', 'status', 'is_private', 'estimated_cost', 'raised_by', 'raised_by_name',
                'assignee_name', 'photo_count', 'has_voice_note', 'accepted_at', 'created_at']
        vals = [q(ASSOC), q(c['ref']), flat(c['flat_number']), q(c['flat_number']), q(c['ticket_type']), q(c['kind']),
                q(c['category']), q(c['title']), q(c['description']), q(c['location']), q(c['criticality']),
                q(c['ai_suggested']), q(c['status']), q(c['is_private']), q(c['estimated_cost']), pid(resolve(c['raised_by_name'])),
                q(c['raised_by_name']), q(c['assignee_name']), q(c['photo_count']), q(c['has_voice_note']),
                q(c['accepted_at']), q(c['created_at'])]
        out.append(f"insert into complaints ({', '.join(cols)}) values ({', '.join(vals)});")
        for r in c['remarks']:
            out.append("insert into complaint_remarks (complaint_id, author, author_name, body, created_at) values "
                       f"((select id from complaints where association_id = '{ASSOC}' and ref = {q(c['ref'])}), "
                       f"{pid(resolve(r['by']))}, {q(r['by'])}, {q(r['body'])}, {q(r['at'])});")
    for a in d['approvals']:
        out.append("insert into approval_requests (association_id, ref, code, title, details, initiator, initiator_name, "
                   "initiator_role, category, mom_required, mom_ref, high_risk, flagged, created_at) values "
                   f"({q(ASSOC)}, {q(a['ref'])}, {q(a['code'])}, {q(a['title'])}, {q(json.dumps(a['details']))}::jsonb, "
                   f"{pid(resolve(a['initiator_name'], 'Anitha Nair'))}, {q(a['initiator_name'])}, '{a['initiator_role']}', "
                   f"{q(a['category'])}, {q(a['mom_required'])}, {q(a['mom_ref'])}, {q(a['high_risk'])}, {q(a['flagged'])}, {q(a['created_at'])});")
        for i, s in enumerate(a['steps'], 1):
            owner_flat = (a['details'].get('Flat') or '').split(' ')[0] if s['role'] == 'owner' else None
            decided = s['decision'] != 'pending'
            decided_at = q(a['created_at']) + "::timestamptz + interval '1 day'"
            who = resolve(s['decided_by'] or s['name'], 'Rajesh Menon') if decided else None
            out.append("insert into approval_steps (request_id, seq, role, alternate_role, name, on_behalf_of, owner_flat, "
                       "decision, decided_by, decided_by_name, comment, decided_at) values "
                       f"((select id from approval_requests where association_id = '{ASSOC}' and ref = {q(a['ref'])}), {i}, "
                       f"'{s['role']}', {q(s['alternate_role'])}{'::app_role' if s['alternate_role'] else ''}, {q(s['name'])}, "
                       f"{q(s['on_behalf_of'])}, {q(owner_flat)}, '{s['decision']}', {pid(who) if who else 'null'}, {q(who)}, "
                       f"{q(s['comment'])}, {decided_at if decided else 'null'});")
    out.append('commit;')
    out.append(f"select 'complaints', count(*) from complaints where association_id = '{ASSOC}' "
               f"union all select 'approvals', count(*) from approval_requests where association_id = '{ASSOC}' "
               f"union all select 'sample users', count(*) from profiles where email like '%@{DOMAIN}';")
    return '\n'.join(out)

def run(sql):
    ref = urllib.parse.urlparse(os.environ['SUPABASE_URL']).hostname.split('.')[0]
    env = os.environ.copy(); env['PGPASSWORD'] = env['SUPABASE_DB_PASSWORD']
    p = subprocess.run(['docker', 'exec', '-i', '-e', 'PGPASSWORD', 'supabase_db_flatsphere-v2', 'psql',
        f'host=aws-0-ap-south-1.pooler.supabase.com port=5432 dbname=postgres user=postgres.{ref} sslmode=require',
        '-v', 'ON_ERROR_STOP=1', '-At'], input=sql, text=True, env=env, capture_output=True)
    print(p.stdout[-1500:], p.stderr[-3000:])

if __name__ == '__main__':
    if sys.argv[1] == 'cleanup':
        run('begin;' + CLEANUP + 'commit;')
    else:
        run(seed_sql(json.load(open(sys.argv[2]))))
