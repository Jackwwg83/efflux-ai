-- 管理员操作审计系统

-- 1. 创建审计日志表
CREATE TABLE IF NOT EXISTS admin_audit_logs (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  admin_user_id uuid NOT NULL,
  action text NOT NULL,
  table_name text,
  record_id uuid,
  old_data jsonb,
  new_data jsonb,
  ip_address inet,
  user_agent text,
  created_at timestamptz DEFAULT now()
);

-- 2. 创建索引
CREATE INDEX idx_admin_audit_logs_admin_user_id ON admin_audit_logs(admin_user_id);
CREATE INDEX idx_admin_audit_logs_created_at ON admin_audit_logs(created_at);
CREATE INDEX idx_admin_audit_logs_action ON admin_audit_logs(action);

-- 3. 创建审计函数
CREATE OR REPLACE FUNCTION log_admin_action(
  p_action text,
  p_table_name text DEFAULT NULL,
  p_record_id uuid DEFAULT NULL,
  p_old_data jsonb DEFAULT NULL,
  p_new_data jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO admin_audit_logs (
    admin_user_id,
    action,
    table_name,
    record_id,
    old_data,
    new_data
  ) VALUES (
    auth.uid(),
    p_action,
    p_table_name,
    p_record_id,
    p_old_data,
    p_new_data
  );
END;
$$;

-- 4. 创建 API Key 操作的触发器
CREATE OR REPLACE FUNCTION audit_api_key_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- 只记录管理员的操作
  IF NOT is_current_user_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    PERFORM log_admin_action(
      'api_key_created',
      'api_key_pool',
      NEW.id,
      NULL,
      to_jsonb(NEW)
    );
  ELSIF TG_OP = 'UPDATE' THEN
    PERFORM log_admin_action(
      'api_key_updated',
      'api_key_pool',
      NEW.id,
      to_jsonb(OLD),
      to_jsonb(NEW)
    );
  ELSIF TG_OP = 'DELETE' THEN
    PERFORM log_admin_action(
      'api_key_deleted',
      'api_key_pool',
      OLD.id,
      to_jsonb(OLD),
      NULL
    );
    RETURN OLD;
  END IF;
  
  RETURN NEW;
END;
$$;

-- 5. 创建触发器
DROP TRIGGER IF EXISTS audit_api_key_changes_trigger ON api_key_pool;
CREATE TRIGGER audit_api_key_changes_trigger
AFTER INSERT OR UPDATE OR DELETE ON api_key_pool
FOR EACH ROW
EXECUTE FUNCTION audit_api_key_changes();

-- 6. 创建用户层级变更的触发器
CREATE OR REPLACE FUNCTION audit_user_tier_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT is_current_user_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    PERFORM log_admin_action(
      'user_tier_set',
      'user_tiers',
      NEW.user_id,
      NULL,
      jsonb_build_object('tier', NEW.tier)
    );
  ELSIF TG_OP = 'UPDATE' THEN
    PERFORM log_admin_action(
      'user_tier_changed',
      'user_tiers',
      NEW.user_id,
      jsonb_build_object('tier', OLD.tier),
      jsonb_build_object('tier', NEW.tier)
    );
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS audit_user_tier_changes_trigger ON user_tiers;
CREATE TRIGGER audit_user_tier_changes_trigger
AFTER INSERT OR UPDATE ON user_tiers
FOR EACH ROW
EXECUTE FUNCTION audit_user_tier_changes();

-- 7. 审计日志的 RLS 策略
ALTER TABLE admin_audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only admins can view audit logs"
ON admin_audit_logs FOR SELECT
TO authenticated
USING (is_current_user_admin());

-- 8. 创建清理旧审计日志的函数（保留90天）
CREATE OR REPLACE FUNCTION cleanup_old_audit_logs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM admin_audit_logs 
  WHERE created_at < now() - interval '90 days';
END;
$$;

-- 9. 授予必要的权限
GRANT EXECUTE ON FUNCTION log_admin_action(text, text, uuid, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION cleanup_old_audit_logs() TO authenticated;