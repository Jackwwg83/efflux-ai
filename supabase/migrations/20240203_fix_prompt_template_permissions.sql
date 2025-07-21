-- Fix prompt template permissions to allow all authenticated users to manage templates

-- Drop existing restrictive policies
DROP POLICY IF EXISTS "Admins can manage prompt templates" ON prompt_templates;

-- Create new policies that allow users to manage templates
CREATE POLICY "Users can create prompt templates" ON prompt_templates
  FOR INSERT 
  TO authenticated
  WITH CHECK (
    created_by = auth.uid() OR 
    created_by IS NULL
  );

CREATE POLICY "Users can update their own templates" ON prompt_templates
  FOR UPDATE 
  TO authenticated
  USING (
    created_by = auth.uid() OR 
    created_by IS NULL OR
    EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
  )
  WITH CHECK (
    created_by = auth.uid() OR 
    created_by IS NULL OR
    EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
  );

CREATE POLICY "Users can delete their own templates" ON prompt_templates
  FOR DELETE 
  TO authenticated
  USING (
    created_by = auth.uid() OR
    EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
  );

-- Ensure everyone can still read active templates
DROP POLICY IF EXISTS "Everyone can read prompt templates" ON prompt_templates;
CREATE POLICY "Everyone can read active prompt templates" ON prompt_templates
  FOR SELECT USING (is_active = true OR created_by = auth.uid());