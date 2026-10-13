select policyname, cmd, roles::text
  from pg_policies
 where schemaname = 'storage' and tablename = 'objects'
 order by policyname;
