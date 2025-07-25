# 统一模型管理系统实施计划

## 概述

将 Efflux-AI 平台从双轨模型管理（直接提供商 + 聚合器）转变为统一的 AI 聚合平台，类似 Raycast 和 POE。

## 核心理念

- **对管理员**：一套统一的管理界面，无需区分模型来源
- **对用户**：完全透明，只需选择模型使用，不关心背后的供给方
- **智能路由**：自动选择最优的 Token 供给源

## 实施步骤

### 第一步：数据库迁移 ✅

1. 运行迁移脚本创建新表结构：
```bash
# 在 Supabase Dashboard 中运行
/supabase/migrations/20250124_unified_model_system.sql
```

2. 执行数据迁移函数：
```sql
SELECT migrate_to_unified_models();
```

### 第二步：更新管理界面 ✅

1. 替换现有的模型管理页面：
```bash
# 备份原文件
mv app/(admin)/admin/models/page.tsx app/(admin)/admin/models/page-backup.tsx

# 使用新的统一界面
mv app/(admin)/admin/models/unified-page.tsx app/(admin)/admin/models/page.tsx
```

2. 创建必要的 RPC 函数（如果还没有）：
```sql
-- 获取所有模型及其供给源
CREATE OR REPLACE FUNCTION get_all_models_with_sources()
RETURNS TABLE (
    model_id TEXT,
    display_name TEXT,
    custom_name TEXT,
    model_type TEXT,
    capabilities JSONB,
    context_window INTEGER,
    max_output_tokens INTEGER,
    input_price DECIMAL,
    output_price DECIMAL,
    tier_required TEXT,
    tags TEXT[],
    is_active BOOLEAN,
    is_featured BOOLEAN,
    health_status TEXT,
    available_sources INTEGER,
    sources JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        m.*,
        COUNT(ms.id)::INTEGER as available_sources,
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'provider_name', ms.provider_name,
                    'provider_type', ms.provider_type,
                    'is_available', ms.is_available,
                    'priority', ms.priority
                ) 
                ORDER BY ms.priority DESC
            ) FILTER (WHERE ms.id IS NOT NULL),
            '[]'::jsonb
        ) as sources
    FROM models m
    LEFT JOIN model_sources ms ON ms.model_id = m.model_id
    GROUP BY m.model_id;
END;
$$ LANGUAGE plpgsql;
```

### 第三步：更新 Edge Function 🚧

1. 集成统一路由器到现有的 v1-chat 函数：
```typescript
// 在 /supabase/functions/v1-chat/index.ts 中添加
import UnifiedModelRouter from './unified-router.ts'

// 初始化路由器
const router = new UnifiedModelRouter(
  Deno.env.get('SUPABASE_URL'),
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
)

// 替换现有的路由逻辑
const route = await router.getOptimalRoute(model, user.id)
const response = await router.forwardRequest({
  route,
  model,
  messages,
  stream,
  temperature,
  max_tokens
})
```

### 第四步：更新用户端模型选择器 🔄

1. 简化模型选择器，移除提供商信息：
```typescript
// 更新 /components/chat/model-selector.tsx
// 使用新的 get_available_models_unified 函数
// 按标签和类型分组，而不是按提供商
```

### 第五步：数据同步优化 🔄

1. 创建统一的同步端点：
```typescript
// /app/api/admin/sync-models/route.ts
export async function POST() {
  // 1. 同步所有直接提供商模型
  // 2. 同步所有聚合器模型
  // 3. 合并并更新 models 表
  // 4. 更新 model_sources 表
}
```

## 关键特性

### 1. 智能路由
- 基于优先级、可用性、成本自动选择供给源
- 负载均衡和故障转移
- 实时性能监控

### 2. 统一定价
- 管理员设置统一的用户价格
- 自动计算利润空间
- 批量价格调整

### 3. 标签系统
- 推荐、热门、新增、视觉、快速等标签
- 用户看到分类清晰的模型列表
- 智能推荐常用模型

### 4. 多源管理
- 一个模型可以有多个供给源
- 自动选择最优源
- 供给源健康监控

## 数据结构变化

### 新增表
- `models` - 统一的模型信息表
- `model_sources` - 模型供给源映射表
- `model_routing_logs` - 路由决策日志

### 保留表（用于兼容）
- `api_key_pool` - API 密钥管理
- `api_providers` - 提供商信息

### 废弃表（迁移后删除）
- `model_configs` - 被 models 表替代
- `aggregator_models` - 被 models + model_sources 替代

## 用户体验改进

### 管理员视角
- 统一的模型列表，可按多个维度筛选
- 批量操作：启用/禁用、定价、标签
- 实时同步所有供给源
- 路由分析和成本报告

### 终端用户视角
- 清晰的模型分类（推荐、快速、强大等）
- 无需关心模型来源
- 统一的使用体验
- 更快的响应速度（智能路由）

## 监控和分析

### 关键指标
- 模型使用频率
- 供给源性能（延迟、成功率）
- 成本分析（收入 vs 支出）
- 用户偏好分析

### 告警机制
- 供给源不可用告警
- 成本异常告警
- 性能下降告警

## 回滚计划

如果需要回滚到原系统：

1. 保留原有表结构不删除
2. 切换回原有的页面组件
3. 恢复原有的 Edge Function 逻辑
4. 数据可以保持同步，不影响运行

## 时间线

- **第 1 周**：数据库迁移和数据同步
- **第 2 周**：管理界面更新和测试
- **第 3 周**：Edge Function 集成和路由优化
- **第 4 周**：用户端更新和全面测试
- **第 5 周**：监控部署和性能优化

## 成功标准

1. ✅ 所有模型在统一界面中管理
2. ✅ 用户无感知的模型使用体验
3. ✅ 智能路由成功率 > 99%
4. ✅ 管理效率提升 50%
5. ✅ 成本透明度 100%