-- Update the avatars bucket configuration
UPDATE storage.buckets
SET file_size_limit = 524288, -- 0.5MB in bytes
    allowed_mime_types = '{image/jpeg,image/png,image/webp}'
WHERE id = 'avatars';