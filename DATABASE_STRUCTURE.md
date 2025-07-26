# Database Structure Documentation

Based on actual diagnostic queries performed on 2025-07-25.

## Tables

### 1. models
**Purpose**: Stores all AI models (unified from both direct providers and aggregators)

**Columns**:
- `id` (uuid) - Primary key
- `model_id` (text) - Unique model identifier (e.g., "gpt-4", "claude-3-opus")
- `display_name` (text) - Human-readable name
- `description` (text, nullable)
- `model_type` (text) - Type of model (e.g., "chat")
- `capabilities` (jsonb, nullable) - Model capabilities
  - Example: `{"vision": false, "functions": true, "json_mode": false, "streaming": true}`
- `context_window` (integer, nullable) - Context window size
- `max_output_tokens` (integer, nullable)
- `training_cutoff` (date, nullable)
- `custom_name` (text, nullable)
- `input_price` (numeric, nullable) - Price per input token
- `output_price` (numeric, nullable) - Price per output token
- `tier_required` (text, nullable) - Required user tier (e.g., "free", "pro")
- `priority` (integer, nullable) - Priority for routing
- `tags` (text[], nullable) - Array of tags (e.g., ["new", "vision", "fast"])
- `is_active` (boolean, nullable)
- `is_featured` (boolean, nullable)
- `health_status` (text, nullable) - Health status (e.g., "healthy")
- `health_message` (text, nullable)
- `created_at` (timestamp with time zone, nullable)
- `updated_at` (timestamp with time zone, nullable)

**Sample Data**:
```json
{
  "id": "5862d7b5-b98a-4ef5-a6ee-6597df1bca14",
  "model_id": "aihubmix-DeepSeek-R1",
  "display_name": "Aihubmix DeepSeek R1",
  "model_type": "chat",
  "capabilities": {
    "vision": false,
    "functions": true,
    "json_mode": false,
    "streaming": true
  },
  "context_window": 32768,
  "input_price": "0.000000",
  "is_active": true,
  "tags": ["new"]
}
```

### 2. model_sources
**Purpose**: Stores provider information for each model (many-to-one relationship with models)

**Columns**:
- `id` (uuid) - Primary key
- `model_id` (text) - References models.model_id (NOT models.id!)
- `provider_type` (text) - "direct" or "aggregator"
- `provider_name` (text) - Provider name (e.g., "openai", "anthropic", "aihubmix")
- `provider_model_id` (text, nullable)
- `original_input_price` (numeric, nullable, default: 0)
- `original_output_price` (numeric, nullable, default: 0)
- `priority` (integer, nullable, default: 0)
- `weight` (integer, nullable, default: 100)
- `api_endpoint` (text, nullable)
- `api_standard` (text, nullable, default: 'openai')
- `custom_headers` (jsonb, nullable, default: '{}')
- `is_available` (boolean, nullable, default: true)
- `last_checked` (timestamp with time zone, nullable)
- `consecutive_failures` (integer, nullable, default: 0)
- `average_latency_ms` (integer, nullable)
- `created_at` (timestamp with time zone, nullable)
- `updated_at` (timestamp with time zone, nullable)

**Important**: `model_sources.model_id` is text type and references `models.model_id` (also text), NOT `models.id` (which is uuid).

### 3. api_key_pool
**Purpose**: Stores API keys for both direct providers and aggregators

**Columns**:
- `id` (uuid) - Primary key
- `provider` (text) - Provider name (e.g., "openai", "aihubmix")
- `api_key` (text) - The actual API key
- `name` (text, nullable) - User-friendly name
- `is_active` (boolean, nullable)
- `rate_limit_remaining` (integer, nullable)
- `rate_limit_reset_at` (timestamp with time zone, nullable)
- `last_used_at` (timestamp with time zone, nullable)
- `error_count` (integer, nullable)
- `consecutive_errors` (integer, nullable)
- `total_requests` (bigint, nullable)
- `total_tokens_used` (bigint, nullable)
- `created_by` (uuid, nullable)
- `created_at` (timestamp with time zone, nullable)
- `updated_at` (timestamp with time zone, nullable)
- `provider_type` (text, nullable) - "direct" or "aggregator"
- `provider_config` (jsonb, nullable) - Additional configuration

**Note**: No `provider_id` column - provider is stored as text directly.

### 4. api_providers
**Purpose**: Stores aggregator provider information

**Columns**:
- `id` (uuid) - Primary key
- `name` (text) - Provider identifier
- `display_name` (text)
- `provider_type` (text) - "aggregator"
- `base_url` (text)
- `api_standard` (text)
- `features` (jsonb, nullable)
- `documentation_url` (text, nullable)
- `created_at` (timestamp with time zone, nullable)
- `updated_at` (timestamp with time zone, nullable)

### 5. admin_users
**Purpose**: Stores admin user IDs

**Columns**:
- `user_id` (uuid) - Primary key, references auth.users
- `created_at` (timestamp with time zone)

## Key Functions

### get_all_models_with_sources()
Returns all models with their source information.

**Return columns**:
- model_id (text)
- display_name (text)
- custom_name (text)
- model_type (text)
- capabilities (jsonb)
- context_window (integer)
- max_output_tokens (integer)
- input_price (numeric)
- output_price (numeric)
- tier_required (text)
- tags (text[])
- is_active (boolean)
- is_featured (boolean)
- health_status (text)
- available_sources (integer)
- sources (jsonb)

### get_provider_health_stats()
Returns health statistics for providers.

**Return columns**:
- provider (text)
- total_keys (integer)
- active_keys (integer)
- total_requests (bigint)
- total_errors (bigint)
- avg_latency (numeric)

### get_all_available_models()
Returns models available to users.

**Return columns**:
- model_id (text)
- model_name (text)
- display_name (text)
- provider (text)
- is_available (boolean)
- supports_vision (boolean)
- supports_functions (boolean)
- context_length (integer)
- max_output_tokens (integer)
- input_price (numeric)
- output_price (numeric)
- currency (text)
- health_status (text)
- tags (text[])

## Important Relationships

1. **models ↔ model_sources**: One-to-many relationship via `model_id` (text field, NOT uuid)
2. **api_key_pool**: Standalone table, `provider` is stored as text
3. **admin_users**: References auth.users for admin privileges

## Common Errors Encountered

1. **Type Mismatch**: `model_sources.model_id` (text) cannot be directly compared with `models.id` (uuid). Must use `models.model_id` for joins.

2. **Missing Columns**: 
   - `api_key_pool` does not have `provider_id` column
   - `api_key_pool` does not have `failed_requests` column (use `error_count` instead)
   - `api_key_pool` does not have latency-related columns

3. **RLS Policies**: All tables have Row Level Security enabled. Admin users need proper entries in `admin_users` table.

## Model Tier System (Updated 2025-07-26)

### Tier Values
The `tier_required` field in the `models` table supports the following values:
- `'free'` - Basic models available to all users
- `'pro'` - Mid-tier models for professional users  
- `'max'` - Premium models with highest capabilities
- `NULL` - Defaults to 'free' behavior

**Check Constraint**: `models_tier_required_check` enforces these values.

### Current Model Distribution (as of 2025-07-26)

After optimization to keep only latest models:

**Total Active Models**: 26 (reduced from 387)

**By Provider**:
- **OpenAI** (9 models):
  - Max tier: o3, o3-pro
  - Pro tier: gpt-4o, o3-mini, o4-mini, gpt-4.1
  - Free tier: gpt-4o-mini, gpt-4.1-mini, gpt-4.1-nano

- **Anthropic** (9 models):
  - Max tier: Claude 4 Opus variants (3)
  - Pro tier: Claude 4 Sonnet variants (3)
  - Free tier: Claude 3.5 Haiku variants (3)

- **Google** (5 models):
  - Max tier: Gemini 2.5 Pro
  - Pro tier: Gemini 2.5 Flash
  - Free tier: Gemini 2.0 Flash, Flash-Lite variants

- **Other** (3 models):
  - Free tier: DALL-E 3, Text Embedding 3 (Small & Large)

**Featured Models**: gpt-4o, o4-mini, claude-opus-4-0, gemini-2.5-pro, gemini-2.5-flash

### Model Naming Patterns
- OpenAI O-series: `o3`, `o3-pro`, `o3-mini`, `o4-mini`
- OpenAI GPT: `gpt-4o`, `gpt-4o-mini`, `gpt-4.1`, `gpt-4.1-mini`, `gpt-4.1-nano`
- Claude 4: `claude-opus-4-0`, `claude-sonnet-4-0`, with dated variants
- Claude 3.5: Only Haiku retained (`claude-3.5-haiku`, `claude-3-5-haiku`)
- Gemini 2.x: `gemini-2.5-pro`, `gemini-2.5-flash`, `gemini-2.0-flash-lite`

### Model Selection Strategy
1. All GPT-3.5 and earlier models removed
2. Claude 3.x models removed except 3.5 Haiku (cheapest) and 3.7 Sonnet (if exists)
3. All Gemini 1.x models removed
4. Only stable versions kept (no preview/experimental/search variants)
5. Price-based tier assignment based on 2025 market rates

## Current Statistics (as of 2025-07-26)
- Total models in database: 387
- Active models: 26
- Model sources: 403
- Current admin user: 76443a23-7734-4500-9cd2-89d685eba7d3