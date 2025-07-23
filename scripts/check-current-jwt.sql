-- 在应用中运行这个查询来检查当前的 JWT 信息
-- 这个查询应该在你登录后，从应用内部执行（不是在 SQL Editor）

SELECT 
    auth.uid() as user_id,
    auth.role() as jwt_role,
    auth.jwt() -> 'raw_user_meta_data' ->> 'role' as admin_role,
    auth.jwt() -> 'session_id' as session_id,
    auth.jwt() -> 'exp' as token_expiry,
    to_timestamp((auth.jwt() -> 'exp')::int) as token_expiry_time,
    auth.jwt() -> 'raw_user_meta_data' as full_metadata;