export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string
          email: string
          full_name: string | null
          avatar_url: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id: string
          email: string
          full_name?: string | null
          avatar_url?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          email?: string
          full_name?: string | null
          avatar_url?: string | null
          created_at?: string
          updated_at?: string
        }
      }
      user_tiers: {
        Row: {
          id: string
          user_id: string
          tier: 'free' | 'pro' | 'max'
          credits_balance: number
          credits_limit: number
          rate_limit: number
          reset_at: string
          stripe_customer_id: string | null
          stripe_subscription_id: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          tier?: 'free' | 'pro' | 'max'
          credits_balance?: number
          credits_limit: number
          rate_limit?: number
          reset_at?: string
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          tier?: 'free' | 'pro' | 'max'
          credits_balance?: number
          credits_limit?: number
          rate_limit?: number
          reset_at?: string
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          created_at?: string
          updated_at?: string
        }
      }
      api_keys: {
        Row: {
          id: string
          provider: string
          api_key: string
          is_active: boolean
          created_by: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          provider: string
          api_key: string
          is_active?: boolean
          created_by?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          provider?: string
          api_key?: string
          is_active?: boolean
          created_by?: string | null
          created_at?: string
          updated_at?: string
        }
      }
      conversations: {
        Row: {
          id: string
          user_id: string
          title: string
          model: string | null
          provider: string | null
          created_at: string
          updated_at: string
          last_message_at: string | null
          is_favorite: boolean | null
          last_message_preview: string | null
          message_count: number | null
          total_tokens: number | null
        }
        Insert: {
          id?: string
          user_id: string
          title?: string
          model?: string | null
          provider?: string | null
          created_at?: string
          updated_at?: string
          last_message_at?: string | null
          is_favorite?: boolean | null
          last_message_preview?: string | null
          message_count?: number | null
          total_tokens?: number | null
        }
        Update: {
          id?: string
          user_id?: string
          title?: string
          model?: string | null
          provider?: string | null
          created_at?: string
          updated_at?: string
          last_message_at?: string | null
          is_favorite?: boolean | null
          last_message_preview?: string | null
          message_count?: number | null
          total_tokens?: number | null
        }
      }
      messages: {
        Row: {
          id: string
          conversation_id: string
          role: 'user' | 'assistant' | 'system'
          content: string
          model: string | null
          provider: string | null
          prompt_tokens: number | null
          completion_tokens: number | null
          total_tokens: number | null
          created_at: string
          metadata: Json | null
          is_pinned: boolean | null
          is_summarized: boolean | null
          summary_of: string[] | null
        }
        Insert: {
          id?: string
          conversation_id: string
          role: 'user' | 'assistant' | 'system'
          content: string
          model?: string | null
          provider?: string | null
          prompt_tokens?: number | null
          completion_tokens?: number | null
          total_tokens?: number | null
          created_at?: string
          metadata?: Json | null
          is_pinned?: boolean | null
          is_summarized?: boolean | null
          summary_of?: string[] | null
        }
        Update: {
          id?: string
          conversation_id?: string
          role?: 'user' | 'assistant' | 'system'
          content?: string
          model?: string | null
          provider?: string | null
          prompt_tokens?: number | null
          completion_tokens?: number | null
          total_tokens?: number | null
          created_at?: string
          metadata?: Json | null
          is_pinned?: boolean | null
          is_summarized?: boolean | null
          summary_of?: string[] | null
        }
      }
      usage_logs: {
        Row: {
          id: string
          user_id: string
          conversation_id: string | null
          message_id: string | null
          model: string
          provider: string
          prompt_tokens: number
          completion_tokens: number
          total_tokens: number
          cost: number
          created_at: string
        }
        Insert: {
          id?: string
          user_id: string
          conversation_id?: string | null
          message_id?: string | null
          model: string
          provider: string
          prompt_tokens?: number
          completion_tokens?: number
          total_tokens?: number
          cost?: number
          created_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          conversation_id?: string | null
          message_id?: string | null
          model?: string
          provider?: string
          prompt_tokens?: number
          completion_tokens?: number
          total_tokens?: number
          cost?: number
          created_at?: string
        }
      }
      model_configs: {
        Row: {
          id: string
          provider: string
          model: string
          display_name: string
          input_price: number
          output_price: number
          max_tokens: number
          context_window: number
          tier_required: 'free' | 'pro' | 'max'
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          provider: string
          model: string
          display_name: string
          input_price: number
          output_price: number
          max_tokens: number
          context_window: number
          tier_required?: 'free' | 'pro' | 'max'
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          provider?: string
          model?: string
          display_name?: string
          input_price?: number
          output_price?: number
          max_tokens?: number
          context_window?: number
          tier_required?: 'free' | 'pro' | 'max'
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
      }
      prompt_templates: {
        Row: {
          id: string
          name: string
          description: string | null
          role: 'default' | 'programming' | 'writing' | 'analysis' | 'creative' | 'educational' | 'custom'
          model_type: 'general' | 'claude' | 'gpt' | 'gemini' | null
          template: string
          variables: Json
          is_active: boolean
          created_by: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          name: string
          description?: string | null
          role: 'default' | 'programming' | 'writing' | 'analysis' | 'creative' | 'educational' | 'custom'
          model_type?: 'general' | 'claude' | 'gpt' | 'gemini' | null
          template: string
          variables?: Json
          is_active?: boolean
          created_by?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          name?: string
          description?: string | null
          role?: 'default' | 'programming' | 'writing' | 'analysis' | 'creative' | 'educational' | 'custom'
          model_type?: 'general' | 'claude' | 'gpt' | 'gemini' | null
          template?: string
          variables?: Json
          is_active?: boolean
          created_by?: string | null
          created_at?: string
          updated_at?: string
        }
      }
      user_prompt_configs: {
        Row: {
          id: string
          user_id: string
          conversation_id: string
          template_id: string | null
          custom_prompt: string | null
          variables: Json
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          conversation_id: string
          template_id?: string | null
          custom_prompt?: string | null
          variables?: Json
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          conversation_id?: string
          template_id?: string | null
          custom_prompt?: string | null
          variables?: Json
          created_at?: string
          updated_at?: string
        }
      }
      message_summaries: {
        Row: {
          id: string
          conversation_id: string
          start_message_id: string | null
          end_message_id: string | null
          message_count: number
          summary_content: string
          summary_tokens: number | null
          original_tokens: number | null
          compression_ratio: number | null
          created_at: string
        }
        Insert: {
          id?: string
          conversation_id: string
          start_message_id?: string | null
          end_message_id?: string | null
          message_count: number
          summary_content: string
          summary_tokens?: number | null
          original_tokens?: number | null
          compression_ratio?: number | null
          created_at?: string
        }
        Update: {
          id?: string
          conversation_id?: string
          start_message_id?: string | null
          end_message_id?: string | null
          message_count?: number
          summary_content?: string
          summary_tokens?: number | null
          original_tokens?: number | null
          compression_ratio?: number | null
          created_at?: string
        }
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      deduct_credits: {
        Args: {
          p_user_id: string
          p_tokens: number
          p_cost: number
        }
        Returns: boolean
      }
      reset_daily_credits: {
        Args: Record<string, never>
        Returns: undefined
      }
    }
    Enums: {
      user_tier: 'free' | 'pro' | 'max'
      message_role: 'user' | 'assistant' | 'system'
    }
  }
}