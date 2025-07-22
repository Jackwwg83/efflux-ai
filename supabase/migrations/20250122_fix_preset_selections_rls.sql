-- Fix RLS policies for user_preset_selections table

-- Drop existing policies if any
DROP POLICY IF EXISTS "Users can manage own preset selections" ON user_preset_selections;
DROP POLICY IF EXISTS "Users can view own preset selections" ON user_preset_selections;
DROP POLICY IF EXISTS "Users can insert own preset selections" ON user_preset_selections;
DROP POLICY IF EXISTS "Users can update own preset selections" ON user_preset_selections;
DROP POLICY IF EXISTS "Users can delete own preset selections" ON user_preset_selections;

-- Enable RLS
ALTER TABLE user_preset_selections ENABLE ROW LEVEL SECURITY;

-- Create separate policies for each operation with null checks
CREATE POLICY "Users can view own preset selections" ON user_preset_selections
  FOR SELECT USING (auth.uid() IS NOT NULL AND auth.uid() = user_id);

CREATE POLICY "Users can insert own preset selections" ON user_preset_selections
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);

CREATE POLICY "Users can update own preset selections" ON user_preset_selections
  FOR UPDATE USING (auth.uid() IS NOT NULL AND auth.uid() = user_id) 
  WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);

CREATE POLICY "Users can delete own preset selections" ON user_preset_selections
  FOR DELETE USING (auth.uid() IS NOT NULL AND auth.uid() = user_id);

-- Also ensure the presets table has proper policies
DROP POLICY IF EXISTS "Everyone can read active presets" ON presets;

CREATE POLICY "Everyone can read active presets" ON presets
  FOR SELECT USING (is_active = true);

-- Ensure preset_categories are readable
DROP POLICY IF EXISTS "Everyone can read preset categories" ON preset_categories;

CREATE POLICY "Everyone can read preset categories" ON preset_categories
  FOR SELECT USING (true);

-- Grant necessary permissions
GRANT SELECT ON preset_categories TO authenticated, anon;
GRANT SELECT ON presets TO authenticated, anon;
GRANT ALL ON user_preset_selections TO authenticated;

-- Also ensure the function has proper permissions
GRANT EXECUTE ON FUNCTION get_preset_for_conversation(UUID, UUID) TO authenticated, anon;