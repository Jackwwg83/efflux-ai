-- Function to update model health status based on source availability
CREATE OR REPLACE FUNCTION update_model_health_status()
RETURNS void AS $$
BEGIN
    -- Update models health status based on their sources
    UPDATE models m
    SET 
        health_status = CASE
            WHEN NOT EXISTS (
                SELECT 1 FROM model_sources ms 
                WHERE ms.model_id = m.model_id 
                AND ms.is_available = true
            ) THEN 'unavailable'
            WHEN EXISTS (
                SELECT 1 FROM model_sources ms 
                WHERE ms.model_id = m.model_id 
                AND ms.is_available = true
                AND ms.consecutive_failures > 3
            ) THEN 'degraded'
            ELSE 'healthy'
        END,
        health_message = CASE
            WHEN NOT EXISTS (
                SELECT 1 FROM model_sources ms 
                WHERE ms.model_id = m.model_id 
                AND ms.is_available = true
            ) THEN 'No available providers'
            WHEN EXISTS (
                SELECT 1 FROM model_sources ms 
                WHERE ms.model_id = m.model_id 
                AND ms.is_available = true
                AND ms.consecutive_failures > 3
            ) THEN 'Some providers experiencing issues'
            ELSE NULL
        END,
        updated_at = NOW()
    WHERE m.is_active = true;
END;
$$ LANGUAGE plpgsql;

-- Test the function
SELECT update_model_health_status();