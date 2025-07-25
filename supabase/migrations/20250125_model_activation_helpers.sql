-- Helper functions for model activation management

-- Function to bulk activate/deactivate models by pattern
CREATE OR REPLACE FUNCTION bulk_update_model_activation(
  pattern text,
  should_activate boolean,
  pattern_type text DEFAULT 'like' -- 'like', 'exact', 'regex'
)
RETURNS TABLE (
  affected_count integer,
  model_ids text[]
) AS $$
DECLARE
  affected_models text[];
  count_affected integer;
BEGIN
  -- Update models based on pattern type
  IF pattern_type = 'exact' THEN
    UPDATE models 
    SET is_active = should_activate
    WHERE model_id = pattern
    RETURNING model_id INTO affected_models;
  ELSIF pattern_type = 'regex' THEN
    UPDATE models 
    SET is_active = should_activate
    WHERE model_id ~ pattern
    RETURNING model_id INTO affected_models;
  ELSE -- default to 'like'
    UPDATE models 
    SET is_active = should_activate
    WHERE model_id LIKE pattern
    RETURNING model_id INTO affected_models;
  END IF;
  
  GET DIAGNOSTICS count_affected = ROW_COUNT;
  
  RETURN QUERY SELECT count_affected, affected_models;
END;
$$ LANGUAGE plpgsql;

-- Function to set recommended defaults (can be called anytime)
CREATE OR REPLACE FUNCTION set_recommended_model_defaults()
RETURNS TABLE (
  status text,
  active_before integer,
  active_after integer,
  models_activated text[],
  models_deactivated text[]
) AS $$
DECLARE
  before_count integer;
  after_count integer;
  activated text[];
  deactivated text[];
BEGIN
  -- Get current active count
  SELECT COUNT(*) INTO before_count FROM models WHERE is_active = true;
  
  -- Track changes
  WITH deactivated_models AS (
    UPDATE models SET is_active = false
    WHERE is_active = true
    AND NOT (
      -- Keep these patterns active
      is_featured = true
      OR model_id LIKE 'gpt-4-turbo%'
      OR model_id LIKE 'gpt-4o%'
      OR model_id = 'gpt-4'
      OR model_id LIKE 'gpt-3.5-turbo-1106'
      OR model_id LIKE 'gpt-3.5-turbo-0125'
      OR model_id LIKE 'claude-3%'
      OR model_id LIKE 'claude-2.1'
      OR model_id LIKE 'gemini%'
      OR model_id LIKE 'llama-3%'
      OR model_id LIKE 'mixtral%'
      OR model_id LIKE 'mistral%'
      OR model_id = 'deepseek-coder-v2'
      OR model_id LIKE 'qwen2%'
      OR model_id = 'command-r-plus'
      OR model_id = 'dall-e-3'
      OR model_id LIKE 'text-embedding-3%'
      OR 'recommended' = ANY(tags)
      OR 'popular' = ANY(tags)
    )
    RETURNING model_id
  )
  SELECT array_agg(model_id) INTO deactivated FROM deactivated_models;
  
  WITH activated_models AS (
    UPDATE models SET is_active = true
    WHERE is_active = false
    AND (
      -- Activate these patterns
      is_featured = true
      OR model_id LIKE 'gpt-4-turbo%'
      OR model_id LIKE 'gpt-4o%'
      OR model_id = 'gpt-4'
      OR model_id LIKE 'gpt-3.5-turbo-1106'
      OR model_id LIKE 'gpt-3.5-turbo-0125'
      OR model_id LIKE 'claude-3%'
      OR model_id LIKE 'claude-2.1'
      OR model_id LIKE 'gemini%'
      OR model_id LIKE 'llama-3%'
      OR model_id LIKE 'mixtral%'
      OR model_id LIKE 'mistral%'
      OR model_id = 'deepseek-coder-v2'
      OR model_id LIKE 'qwen2%'
      OR model_id = 'command-r-plus'
      OR model_id = 'dall-e-3'
      OR model_id LIKE 'text-embedding-3%'
      OR 'recommended' = ANY(tags)
      OR 'popular' = ANY(tags)
    )
    RETURNING model_id
  )
  SELECT array_agg(model_id) INTO activated FROM activated_models;
  
  -- Get new active count
  SELECT COUNT(*) INTO after_count FROM models WHERE is_active = true;
  
  RETURN QUERY 
  SELECT 
    'Recommended defaults applied'::text as status,
    before_count,
    after_count,
    COALESCE(activated, ARRAY[]::text[]),
    COALESCE(deactivated, ARRAY[]::text[]);
END;
$$ LANGUAGE plpgsql;

-- Function to get model groups for easier management
CREATE OR REPLACE FUNCTION get_model_groups()
RETURNS TABLE (
  group_name text,
  model_count bigint,
  active_count bigint,
  example_models text[]
) AS $$
BEGIN
  RETURN QUERY
  WITH model_groups AS (
    SELECT 
      CASE 
        WHEN model_id LIKE 'gpt-4%' THEN 'GPT-4 Family'
        WHEN model_id LIKE 'gpt-3.5%' THEN 'GPT-3.5 Family'
        WHEN model_id LIKE 'claude-%' THEN 'Claude Family'
        WHEN model_id LIKE 'gemini%' THEN 'Gemini Family'
        WHEN model_id LIKE 'llama%' THEN 'Llama Family'
        WHEN model_id LIKE 'mistral%' OR model_id LIKE 'mixtral%' THEN 'Mistral Family'
        WHEN model_id LIKE 'qwen%' THEN 'Qwen Family'
        WHEN model_id LIKE 'dall-e%' OR model_id LIKE 'stable-diffusion%' THEN 'Image Generation'
        WHEN model_id LIKE '%embedding%' THEN 'Embedding Models'
        WHEN model_id LIKE 'command%' THEN 'Cohere Family'
        ELSE 'Other Models'
      END as family,
      model_id,
      is_active
    FROM models
  )
  SELECT 
    family as group_name,
    COUNT(*)::bigint as model_count,
    COUNT(*) FILTER (WHERE is_active = true)::bigint as active_count,
    (array_agg(model_id ORDER BY model_id))[1:3] as example_models
  FROM model_groups
  GROUP BY family
  ORDER BY 
    CASE family
      WHEN 'GPT-4 Family' THEN 1
      WHEN 'GPT-3.5 Family' THEN 2
      WHEN 'Claude Family' THEN 3
      WHEN 'Gemini Family' THEN 4
      ELSE 99
    END;
END;
$$ LANGUAGE plpgsql;

-- Create index for better performance on model queries
CREATE INDEX IF NOT EXISTS idx_models_active_featured ON models(is_active, is_featured);
CREATE INDEX IF NOT EXISTS idx_models_tags ON models USING GIN(tags);

COMMENT ON FUNCTION bulk_update_model_activation IS 'Bulk activate or deactivate models based on pattern matching. Supports like, exact, and regex patterns.';
COMMENT ON FUNCTION set_recommended_model_defaults IS 'Apply recommended default activation settings. Activates only popular and recent models.';
COMMENT ON FUNCTION get_model_groups IS 'Get model statistics grouped by family/provider for easier management.';