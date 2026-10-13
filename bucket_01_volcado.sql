select policyname, cmd, roles::text, qual, with_check
  from pg_policies
 where schemaname = 'storage' and tablename = 'objects'
 order by policyname;
