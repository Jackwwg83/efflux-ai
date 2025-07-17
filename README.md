# Efflux AI - Multi-Model AI Chat Platform

A SaaS platform that provides access to multiple AI models (OpenAI, Anthropic, Google Gemini, AWS Bedrock) with a unified interface and tier-based access control.

## Features

- 🤖 Multiple AI model support (GPT-4, Claude, Gemini, Bedrock)
- 👥 User authentication (Email, Google, Apple)
- 💳 Tier-based access (Free, Pro, Max)
- 📊 Usage tracking and credits system
- 🔒 Secure API key management
- ⚡ Real-time streaming responses
- 🌐 Edge Functions for API proxy

## Tech Stack

- **Frontend**: Next.js 14 (App Router), TypeScript, Tailwind CSS
- **Backend**: Supabase (PostgreSQL, Edge Functions, Auth)
- **Deployment**: Vercel (Frontend), Supabase (Backend)
- **UI Components**: shadcn/ui
- **State Management**: Zustand + React Query

## Getting Started

### Prerequisites

- Node.js 18+
- npm or yarn
- Supabase account
- Vercel account (for deployment)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/efflux-ai.git
cd efflux-ai
```

2. Install dependencies:
```bash
npm install
```

3. Set up environment variables:
```bash
cp .env.example .env.local
```

4. Update `.env.local` with your Supabase credentials

5. Run the development server:
```bash
npm run dev
```

### Database Setup

1. Create a new Supabase project
2. Run the migrations in `supabase/migrations/`
3. Set up authentication providers (Google, Apple)
4. Deploy Edge Functions

## Project Structure

```
efflux-ai/
├── app/                    # Next.js app directory
│   ├── (auth)/            # Authentication pages
│   ├── (dashboard)/       # Protected dashboard pages
│   └── api/               # API routes
├── components/            # React components
├── lib/                   # Utility functions
│   ├── supabase/         # Supabase client
│   └── ai/               # AI provider integrations
├── supabase/             # Supabase configuration
│   ├── functions/        # Edge Functions
│   └── migrations/       # Database migrations
└── types/                # TypeScript types
```

## User Tiers

- **Free**: 5,000 tokens/day, basic models
- **Pro**: 500,000 tokens/day, advanced models
- **Max**: 5,000,000 tokens/day, all models

## Deployment

### Frontend (Vercel)

1. Connect GitHub repository to Vercel
2. Configure environment variables
3. Deploy

### Backend (Supabase)

1. Install Supabase CLI
2. Link to your project
3. Deploy Edge Functions:
```bash
supabase functions deploy
```

## Contributing

Pull requests are welcome. For major changes, please open an issue first.

## License

MIT