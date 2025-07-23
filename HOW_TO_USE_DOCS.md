# 如何使用项目文档指南

## 🎯 给未来 Claude 实例的指引

当你开始处理这个项目时，请按以下步骤使用文档：

### 1. 首次接触项目时

```bash
# 1. 首先阅读整体架构
/read efflux-ai/ARCHITECTURE_ANALYSIS.md

# 2. 然后查看函数索引
/read efflux-ai/FUNCTION_INDEX.md

# 3. 最后看具体指导
/read CLAUDE.md
```

### 2. 需要修改特定功能时

#### 示例：修改聊天功能
```bash
# 1. 在 FUNCTION_INDEX.md 中搜索 "聊天功能"
/grep "聊天功能" efflux-ai/FUNCTION_INDEX.md

# 2. 找到相关函数后，查看具体实现
/read efflux-ai/supabase/functions/v1-chat/index.ts
```

#### 示例：修改模型管理
```bash
# 1. 在 ARCHITECTURE_ANALYSIS.md 中查看 "模型管理" 部分
/grep "模型管理" efflux-ai/ARCHITECTURE_ANALYSIS.md

# 2. 在 FUNCTION_INDEX.md 中找相关函数
/grep "get_all_available_models\|ModelSync" efflux-ai/FUNCTION_INDEX.md
```

### 3. 遇到问题时的查询方式

#### 问题：不知道某个表的结构
```bash
# 查看数据库架构部分
/grep "Database Schema Architecture" efflux-ai/ARCHITECTURE_ANALYSIS.md -A 50
```

#### 问题：不清楚数据流向
```bash
# 查看关键数据流部分
/grep "关键数据流\|Current Implementation Logic" efflux-ai/ARCHITECTURE_ANALYSIS.md -A 30
```

#### 问题：找不到某个功能的入口
```bash
# 在函数索引中按功能分类查找
/grep "按功能分类" efflux-ai/FUNCTION_INDEX.md -A 50
```

### 4. 常见任务的文档使用模式

#### 任务：添加新的 AI 提供商
1. 查看现有聚合器实现：
   ```bash
   /grep "AiHubMixProvider" efflux-ai/FUNCTION_INDEX.md
   ```
2. 查看架构中的提供商系统：
   ```bash
   /grep "Dual Provider System" efflux-ai/ARCHITECTURE_ANALYSIS.md
   ```

#### 任务：修复 Bug
1. 先查看已知问题：
   ```bash
   /grep "Identified Structural Issues\|Critical Issues" efflux-ai/ARCHITECTURE_ANALYSIS.md
   ```
2. 找到相关函数：
   ```bash
   # 使用函数索引的快速查找
   /grep "快速查找索引" efflux-ai/FUNCTION_INDEX.md -A 100
   ```

#### 任务：性能优化
1. 查看性能问题分析：
   ```bash
   /grep "Performance Issues\|性能问题" efflux-ai/ARCHITECTURE_ANALYSIS.md
   ```
2. 找到相关函数和优化建议

### 5. 更新文档的时机

当你完成以下操作时，请更新相应文档：

#### 需要更新 ARCHITECTURE_ANALYSIS.md：
- 修改了数据库架构
- 改变了主要数据流
- 解决了文档中列出的问题
- 发现了新的结构性问题

#### 需要更新 FUNCTION_INDEX.md：
- 添加了新的数据库函数
- 创建了新的 TypeScript 类或函数
- 添加了新的 API 端点
- 删除或重命名了函数

### 6. 引用文档的最佳实践

在与用户交流时：
```markdown
根据 ARCHITECTURE_ANALYSIS.md 中的说明，当前系统采用...

如 FUNCTION_INDEX.md 所示，处理聊天请求的函数是...

正如文档中提到的已知问题 #3...
```

### 7. 快速命令参考

```bash
# 查看所有数据库函数
/grep "CREATE.*FUNCTION" efflux-ai/supabase/migrations -n

# 查看所有 TypeScript 导出函数
/grep "export.*function\|export.*class" efflux-ai/lib -n

# 查看特定问题的详细信息
/grep "Issue.*[0-9]" efflux-ai/ARCHITECTURE_ANALYSIS.md -A 10

# 查看某个功能的完整实现链
/grep "聊天请求流程\|模型同步流程" efflux-ai/FUNCTION_INDEX.md -A 20
```

## 💡 提示

1. **先看文档，后改代码** - 避免重复已知的错误
2. **理解架构，再做修改** - 确保修改符合整体设计
3. **更新文档，保持同步** - 为下一个开发者（可能是另一个 Claude）留下线索

记住：这些文档是你的"记忆"，好好利用它们！