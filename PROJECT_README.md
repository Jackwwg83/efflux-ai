# Efflux AI

A modern multi-model AI chat platform built with Next.js and Supabase.

## Features

- 🤖 Multi-model support (Gemini, OpenAI, Claude, AWS Bedrock)
- 🔐 Secure authentication (Email/Password, Google OAuth)
- 💳 Tiered user system (Free, Pro, Max)
- 🎯 Credit-based usage tracking
- 🚀 Serverless architecture with Edge Functions
- 💬 Real-time streaming responses

## Tech Stack

- **Frontend**: Next.js 14 (App Router), TypeScript, Tailwind CSS
- **Backend**: Supabase (PostgreSQL, Auth, Edge Functions)
- **Deployment**: Vercel (Frontend), Supabase (Backend)
- **UI Components**: shadcn/ui

## Getting Started

### Prerequisites

- Node.js 18+
- npm or yarn
- Supabase account
- Vercel account (for deployment)

### Local Development

1. Clone the repository:
```bash
git clone https://github.com/Jackwwg83/efflux-ai.git
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

4. Update `.env.local` with your Supabase credentials:
```
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_KEY=your_service_key
```

5. Run the development server:
```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) to see the application.

## Deployment

### Frontend (Vercel)

The frontend is automatically deployed to Vercel when you push to the `main` branch.

### Backend (Supabase)

1. Create a Supabase project
2. Run the database migrations
3. Deploy Edge Functions using Supabase CLI
4. Configure authentication providers

See `SETUP_GUIDE.md` for detailed deployment instructions.

## Project Structure

```
efflux-ai/
├── app/                    # Next.js App Router
│   ├── (admin)/           # Admin routes
│   ├── (auth)/            # Authentication routes
│   └── (dashboard)/       # Main app routes
├── components/            # React components
├── lib/                   # Utilities and libraries
├── supabase/             # Supabase configuration
└── types/                # TypeScript types
```

## User Tiers

- **Free**: 5,000 credits/day, basic models
- **Pro**: 50,000 credits/day, advanced models
- **Max**: 500,000 credits/day, all models

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details.

## Support

For support, please open an issue on GitHub or contact the maintainers.

---

Built with ❤️ using Next.js and Supabase