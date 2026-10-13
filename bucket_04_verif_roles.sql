select roles::text as rol,
       cmd,
       count(*) as politicas,
       string_agg(policyname, ', ' order by policyname) as nombres
  from pg_policies
 where schemaname = 'storage' and tablename = 'objects'
 group by roles::text, cmd
 order by rol, cmd;
