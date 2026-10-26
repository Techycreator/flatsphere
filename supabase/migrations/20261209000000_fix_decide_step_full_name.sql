-- decide_step_family_base declares a variable named full_name, which clashed with the profiles column when saving a decision.
do $t$
declare def text;
begin
  select pg_get_functiondef('public.decide_step_family_base(uuid,decision,text)'::regprocedure) into def;
  def := replace(def, '(select full_name from profiles where id = auth.uid())', '(select p.full_name from profiles p where p.id = auth.uid())');
  if def not like '%select p.full_name from profiles p%' then raise exception 'decide_step_family_base text not found'; end if;
  execute def;
end $t$;