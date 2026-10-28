-- The person who raised a request is part of the EC and their vote counts like anyone else's.
do $$
declare fn text; def text;
begin
  for fn in select unnest(array['ec_vote_summary(uuid)', 'cast_ec_vote(uuid,text,text)']) loop
    def := pg_get_functiondef(('public.' || fn)::regprocedure);
    def := replace(def, 'ec_voter_ids(r.association_id, r.initiator)', 'ec_voter_ids(r.association_id, null)');
    def := replace(def, E'  if v = r.initiator then raise exception ''not_allowed: the person who raised this request cannot vote''; end if;\n', '');
    execute def;
  end loop;
end $$;
