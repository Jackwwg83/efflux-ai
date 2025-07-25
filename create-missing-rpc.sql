-- Create the missing RPC function that the frontend is expecting
CREATE OR REPLACE FUNCTION get_all_models_with_sources()
RETURNS TABLE (
  model_id text,
  display_name text,
  custom_name text,
  model_type text,
  capabilities jsonb,
  context_window integer,
  max_output_tokens integer,
  input_price numeric,
  output_price numeric,
  tier_required text,
  tags text[],
  is_active boolean,
  is_featured boolean,
  health_status text,
  available_sources integer,
  sources jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH model_source_info AS (
    SELECT 
      m.id as model_id_uuid,
      COUNT(DISTINCT ms.id) as source_count,
      jsonb_agg(
        jsonb_build_object(
          'provider_name', ms.provider_name,
          'provider_type', ms.provider_type,
          'is_available', ms.is_available,
          'priority', ms.priority
        ) ORDER BY ms.priority DESC
      ) as source_list
    FROM models m
    LEFT JOIN model_sources ms ON ms.model_id = m.id
    GROUP BY m.id
  )
  SELECT 
    m.model_id,
    m.display_name,
    m.custom_name,
    COALESCE(m.model_type, 'chat') as model_type,
    COALESCE(m.capabilities, '{"supports_chat": true}'::jsonb) as capabilities,
    COALESCE(m.context_window, 4096) as context_window,
    m.max_output_tokens,
    COALESCE(m.input_price, 0) as input_price,
    COALESCE(m.output_price, 0) as output_price,
    COALESCE(m.tier_required, 'free') as tier_required,
    COALESCE(m.tags, ARRAY['new']) as tags,
    COALESCE(m.is_active, false) as is_active,
    COALESCE(m.is_featured, false) as is_featured,
    COALESCE(m.health_status, 'unknown') as health_status,
    COALESCE(msi.source_count, 0)::integer as available_sources,
    COALESCE(msi.source_list, '[]'::jsonb) as sources
  FROM models m
  LEFT JOIN model_source_info msi ON msi.model_id_uuid = m.id
  ORDER BY 
    m.is_featured DESC,
    m.is_active DESC,
    m.priority DESC,
    m.model_id;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION get_all_models_with_sources() TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_models_with_sources() TO anon;

-- Also create a function to update model configuration
CREATE OR REPLACE FUNCTION update_model_config(
  p_model_id text,
  p_custom_name text DEFAULT NULL,
  p_input_price numeric DEFAULT NULL,
  p_output_price numeric DEFAULT NULL,
  p_tier_required text DEFAULT NULL,
  p_tags text[] DEFAULT NULL,
  p_is_active boolean DEFAULT NULL,
  p_is_featured boolean DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE models
  SET 
    custom_name = COALESCE(p_custom_name, custom_name),
    input_price = COALESCE(p_input_price, input_price),
    output_price = COALESCE(p_output_price, output_price),
    tier_required = COALESCE(p_tier_required, tier_required),
    tags = COALESCE(p_tags, tags),
    is_active = COALESCE(p_is_active, is_active),
    is_featured = COALESCE(p_is_featured, is_featured),
    updated_at = now()
  WHERE model_id = p_model_id;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION update_model_config TO authenticated;