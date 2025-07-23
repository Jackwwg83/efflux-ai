-- Fix RLS policies for api_providers table

-- First, ensure RLS is enabled
ALTER TABLE api_providers ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "api_providers_admin_all" ON api_providers;
DROP POLICY IF EXISTS "api_providers_select_all" ON api_providers;

-- Create a policy that allows authenticated users to read all providers
CREATE POLICY "api_providers_read_all" ON api_providers
    FOR SELECT TO authenticated
    USING (true);

-- Create a policy that allows only admins to insert/update/delete
CREATE POLICY "api_providers_admin_write" ON api_providers
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

CREATE POLICY "api_providers_admin_update" ON api_providers
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

CREATE POLICY "api_providers_admin_delete" ON api_providers
    FOR DELETE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

-- Also fix the get_provider_health_stats function
CREATE OR REPLACE FUNCTION get_provider_health_stats()
RETURNS TABLE (
    provider TEXT,
    total_keys INTEGER,
    active_keys INTEGER,
    total_requests BIGINT,
    total_errors BIGINT,
    avg_latency NUMERIC
) 
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        akp.provider,
        COUNT(*)::INTEGER as total_keys,
        SUM(CASE WHEN akp.is_active THEN 1 ELSE 0 END)::INTEGER as active_keys,
        COALESCE(SUM(akp.total_requests), 0) as total_requests,
        COALESCE(SUM(akp.error_count), 0) as total_errors,
        COALESCE(AVG(akp.average_latency_ms), 0) as avg_latency
    FROM api_key_pool akp
    GROUP BY akp.provider;
END;
$$ LANGUAGE plpgsql;