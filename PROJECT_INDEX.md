# 📚 Efflux AI - Project Documentation Index

> A comprehensive guide to the Efflux AI codebase, architecture, and development practices.

## 🏗️ Project Overview

**Efflux AI** is a modern multi-model AI chat platform that provides a seamless interface for interacting with various AI models including Google Gemini, OpenAI GPT, Anthropic Claude, and AWS Bedrock models.

### Key Features
- 🤖 **Multi-Model Support**: Unified interface for multiple AI providers
- 🔐 **Secure Authentication**: Email/Password and Google OAuth integration
- 💳 **Tiered System**: Free, Pro, and Max user tiers with different quotas
- 📊 **Usage Tracking**: Token-based quota management with daily/monthly limits
- 🚀 **Serverless Architecture**: Edge Functions for scalable AI processing
- 💬 **Real-time Streaming**: Server-Sent Events for responsive chat experience

## 📁 Project Structure

```
efflux-ai/
├── 📱 app/                    # Next.js App Router
│   ├── (admin)/              # Admin dashboard routes
│   ├── (auth)/               # Authentication pages
│   └── (dashboard)/          # Main application routes
│       ├── chat/             # Chat interface
│       ├── settings/         # User settings
│       └── billing/          # Subscription management
├── 🧩 components/            # React components
│   ├── chat/                 # Chat-specific components
│   ├── layout/               # Layout components
│   └── ui/                   # Reusable UI components
├── 📚 lib/                   # Core libraries
│   ├── ai/                   # AI provider integrations
│   ├── supabase/             # Database client setup
│   ├── stores/               # State management
│   └── utils/                # Utility functions
├── 🗄️ supabase/             # Backend configuration
│   ├── functions/            # Edge Functions
│   └── migrations/           # Database schema
└── 📝 types/                # TypeScript definitions
```

## 🔧 Core Technologies

### Frontend Stack
- **Framework**: Next.js 14 with App Router
- **Language**: TypeScript
- **Styling**: Tailwind CSS + shadcn/ui
- **State**: React hooks + Zustand (conversation store)
- **Deployment**: Vercel

### Backend Stack
- **Database**: PostgreSQL (via Supabase)
- **Auth**: Supabase Auth (Email + Google OAuth)
- **Edge Functions**: Deno runtime
- **Real-time**: Server-Sent Events
- **Deployment**: Supabase Cloud

## 📋 Documentation Files

### Setup & Deployment
- 📄 **[README.md](./README.md)** - Supabase CLI documentation (needs update)
- 📄 **[PROJECT_README.md](./PROJECT_README.md)** - Project overview and quick start
- 📄 **[QUICKSTART.md](./QUICKSTART.md)** - Quick setup guide
- 📄 **[SETUP_GUIDE.md](./SETUP_GUIDE.md)** - Detailed setup instructions
- 📄 **[DEPLOYMENT.md](./DEPLOYMENT.md)** - Deployment procedures
- 📄 **[VERCEL_DEPLOYMENT.md](./VERCEL_DEPLOYMENT.md)** - Vercel-specific deployment

### Development Guides
- 📄 **[APPLY_MIGRATION.md](./APPLY_MIGRATION.md)** - Database migration guide
- 📄 **[FIX_TOKEN_USAGE.md](./FIX_TOKEN_USAGE.md)** - Token usage troubleshooting
- 📄 **[DATABASE_ISSUES_ANALYSIS.md](./DATABASE_ISSUES_ANALYSIS.md)** - Database schema analysis
- 📄 **[DEPLOY_EDGE_FUNCTIONS.md](./DEPLOY_EDGE_FUNCTIONS.md)** - Edge function deployment

## 🏛️ Architecture

### Data Flow
```
User → Next.js Frontend → Supabase Edge Function → AI Provider
                ↓                    ↓
            Supabase DB         Response Stream
```

### Database Schema

#### Core Tables
- **users** - Managed by Supabase Auth
- **conversations** - Chat conversation metadata
- **messages** - Individual chat messages
- **user_tiers** - User subscription tiers
- **user_quotas** - Token usage tracking
- **api_key_pool** - Encrypted API keys
- **usage_logs** - Detailed usage analytics

#### Key Relationships
```
users (1) ─── (n) conversations
conversations (1) ─── (n) messages
users (1) ─── (1) user_tiers
users (1) ─── (1) user_quotas
```

### Quota System

The platform uses a dual quota tracking system:
1. **Legacy System**: Credits-based (user_tiers.credits_balance)
2. **Modern System**: Token-based (user_quotas.tokens_used_*)

Current tier limits:
- **Free**: 10,000 tokens/day, 100,000 tokens/month
- **Pro**: 100,000 tokens/day, 2,000,000 tokens/month
- **Max**: 500,000 tokens/day, 10,000,000 tokens/month

## 🔌 API Reference

### Edge Functions

#### `/v1-chat` - Main Chat API
```typescript
POST /v1-chat
Headers:
  - Authorization: Bearer <supabase_jwt>
  - Content-Type: application/json

Body: {
  messages: Message[]
  model: string
  temperature?: number
  max_tokens?: number
  stream?: boolean
}

Response: Server-Sent Events stream
```

### Frontend Routes

#### Public Routes
- `/` - Landing page
- `/login` - User login
- `/signup` - User registration
- `/forgot-password` - Password reset

#### Protected Routes
- `/chat` - Main chat interface
- `/settings` - User settings & API keys
- `/billing` - Subscription management
- `/admin/*` - Admin dashboard (restricted)

## 🧩 Key Components

### Chat Components
- **ChatContainer** - Main chat interface orchestrator
- **MessageList** - Renders conversation history
- **MessageInput** - User input with model selection
- **ModelSelector** - AI model picker with provider info
- **PresetSelector** - System prompt presets

### Layout Components
- **DashboardWrapper** - Main app layout with sidebar
- **ConversationSidebar** - Conversation history navigation
- **Header** - Top navigation with user menu

### Utility Components
- **ErrorBoundary** - Global error handling
- **ContextIndicator** - Token usage display
- **PromptSelector** - Quick prompt templates

## 🔐 Security

### API Key Management
- Client-side encryption using Web Crypto API
- Keys stored encrypted in Supabase
- Never exposed in client code or logs

### Authentication
- JWT-based authentication via Supabase
- Row Level Security (RLS) on all tables
- Admin role for privileged operations

### Rate Limiting
- Token-based quotas per tier
- Request rate limiting in Edge Functions
- Automatic quota reset (daily/monthly)

## 🚀 Development Workflow

### Local Development
```bash
# Install dependencies
npm install

# Set up environment
cp .env.example .env.local

# Run development server
npm run dev
```

### Database Changes
```bash
# Create migration
supabase migration new <migration_name>

# Apply migrations
supabase db push
```

### Edge Function Deployment
```bash
# Deploy specific function
npm run deploy:functions

# Or manually
SUPABASE_ACCESS_TOKEN="..." npx supabase functions deploy v1-chat --no-verify-jwt
```

## 📊 Monitoring & Analytics

### Usage Tracking
- Token usage per request
- Model usage distribution
- Cost tracking per user
- Daily/monthly aggregations

### Error Tracking
- Comprehensive error logging
- User context preservation
- Error categorization

## 🔄 Recent Updates

### Latest Features
1. **Preset System** - Customizable system prompts
2. **Improved Quota Management** - Real-time usage tracking
3. **Enhanced Error Handling** - Better error boundaries
4. **Admin Dashboard** - User management interface

### Known Issues
1. Streaming responses occasionally don't send `[DONE]` signal
2. Quota reset timing can be inconsistent
3. Preset selection state management needs improvement

## 📚 Additional Resources

### Internal Documentation
- Database schema definitions in `/supabase/migrations/`
- Type definitions in `/types/database.types.ts`
- Component documentation in source files

### External Resources
- [Next.js Documentation](https://nextjs.org/docs)
- [Supabase Documentation](https://supabase.com/docs)
- [Vercel Documentation](https://vercel.com/docs)
- [shadcn/ui Components](https://ui.shadcn.com)

## 🤝 Contributing

### Code Style
- TypeScript with strict mode
- ESLint configuration for consistency
- Prettier for formatting
- Conventional commits

### Testing
- Component testing (to be implemented)
- E2E testing (to be implemented)
- Manual testing checklist in PR template

### Deployment Process
1. Push to `main` branch
2. Vercel automatically deploys frontend
3. Manually deploy Edge Functions if changed
4. Run database migrations if needed

---

*Last Updated: July 2025*
*Maintained by: Efflux AI Team*