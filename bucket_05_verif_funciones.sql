select p.proname, p.proconfig, p.prosecdef
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('auth_barberia_id','auth_rol')
 order by p.proname;
