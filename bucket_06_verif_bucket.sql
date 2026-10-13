select id, public, file_size_limit, allowed_mime_types
  from storage.buckets
 where id = 'fotos';
