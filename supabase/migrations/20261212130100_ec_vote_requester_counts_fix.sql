do $$
declare def text;
begin
  def := pg_get_functiondef('public.cast_ec_vote(uuid,text,text)'::regprocedure);
  def := regexp_replace(def, E'\\n\\s*if v = r\\.initiator then raise exception ''not_allowed: the person who raised this request cannot vote''; end if;', '');
  if def like '%cannot vote%' then raise exception 'patch failed'; end if;
  execute def;
end $$;
