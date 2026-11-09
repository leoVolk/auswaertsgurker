export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      away_games: {
        Row: {
          club_id: string
          created_at: string
          id: string
          kickoff_at: string | null
          league_shortcut: string
          matchday: number
          openligadb_match_id: number
          opponent_name: string
          personal_data_purged_at: string | null
          season: number
        }
        Insert: {
          club_id: string
          created_at?: string
          id?: string
          kickoff_at?: string | null
          league_shortcut: string
          matchday: number
          openligadb_match_id: number
          opponent_name: string
          personal_data_purged_at?: string | null
          season: number
        }
        Update: {
          club_id?: string
          created_at?: string
          id?: string
          kickoff_at?: string | null
          league_shortcut?: string
          matchday?: number
          openligadb_match_id?: number
          opponent_name?: string
          personal_data_purged_at?: string | null
          season?: number
        }
        Relationships: [
          {
            foreignKeyName: "away_games_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
        ]
      }
      club_invites: {
        Row: {
          club_id: string
          created_at: string
          created_by: string | null
          id: string
          revoked_at: string | null
          token: string
        }
        Insert: {
          club_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          revoked_at?: string | null
          token?: string
        }
        Update: {
          club_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          revoked_at?: string | null
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "club_invites_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "club_invites_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      club_members: {
        Row: {
          club_id: string
          joined_at: string
          role: Database["public"]["Enums"]["club_role"]
          user_id: string
        }
        Insert: {
          club_id: string
          joined_at?: string
          role?: Database["public"]["Enums"]["club_role"]
          user_id: string
        }
        Update: {
          club_id?: string
          joined_at?: string
          role?: Database["public"]["Enums"]["club_role"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "club_members_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "club_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      clubs: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          league_shortcut: string | null
          name: string
          paypal_me: string | null
          team_id: number | null
          team_name: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          league_shortcut?: string | null
          name: string
          paypal_me?: string | null
          team_id?: number | null
          team_name?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          league_shortcut?: string | null
          name?: string
          paypal_me?: string | null
          team_id?: number | null
          team_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clubs_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          attempts: number
          body: string
          claimed_at: string | null
          club_id: string | null
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["notification_kind"]
          last_error: string | null
          sent_at: string | null
          status: Database["public"]["Enums"]["notification_status"]
          title: string
          url: string
          user_id: string
        }
        Insert: {
          attempts?: number
          body: string
          claimed_at?: string | null
          club_id?: string | null
          created_at?: string
          id?: string
          kind: Database["public"]["Enums"]["notification_kind"]
          last_error?: string | null
          sent_at?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          title: string
          url: string
          user_id: string
        }
        Update: {
          attempts?: number
          body?: string
          claimed_at?: string | null
          club_id?: string | null
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["notification_kind"]
          last_error?: string | null
          sent_at?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          title?: string
          url?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          display_name: string | null
          email_notifications: boolean
          id: string
        }
        Insert: {
          created_at?: string
          display_name?: string | null
          email_notifications?: boolean
          id: string
        }
        Update: {
          created_at?: string
          display_name?: string | null
          email_notifications?: boolean
          id?: string
        }
        Relationships: []
      }
      push_subscriptions: {
        Row: {
          auth: string
          created_at: string
          endpoint: string
          id: string
          p256dh: string
          user_agent: string | null
          user_id: string
        }
        Insert: {
          auth: string
          created_at?: string
          endpoint: string
          id?: string
          p256dh: string
          user_agent?: string | null
          user_id: string
        }
        Update: {
          auth?: string
          created_at?: string
          endpoint?: string
          id?: string
          p256dh?: string
          user_agent?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "push_subscriptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      ticket_categories: {
        Row: {
          club_id: string
          created_at: string
          id: string
          name: string
          price_cents: number
          quota: number | null
          round_id: string
          sort_order: number
        }
        Insert: {
          club_id: string
          created_at?: string
          id?: string
          name: string
          price_cents: number
          quota?: number | null
          round_id: string
          sort_order?: number
        }
        Update: {
          club_id?: string
          created_at?: string
          id?: string
          name?: string
          price_cents?: number
          quota?: number | null
          round_id?: string
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "ticket_categories_round_id_club_id_fkey"
            columns: ["round_id", "club_id"]
            isOneToOne: false
            referencedRelation: "ticket_rounds"
            referencedColumns: ["id", "club_id"]
          },
        ]
      }
      ticket_requests: {
        Row: {
          category_id: string
          club_id: string
          created_at: string
          delivery_method:
            | Database["public"]["Enums"]["ticket_delivery_method"]
            | null
          holder_membership_number: string | null
          holder_name: string
          id: string
          payment_amount_cents: number | null
          payment_status: Database["public"]["Enums"]["payment_status"]
          payment_status_changed_at: string | null
          pickup_at: string | null
          pickup_location: string | null
          requested_by: string
          round_id: string
          status: Database["public"]["Enums"]["ticket_status"]
          status_changed_at: string
          ticket_file_path: string | null
          ticket_file_uploaded_at: string | null
        }
        Insert: {
          category_id: string
          club_id: string
          created_at?: string
          delivery_method?:
            | Database["public"]["Enums"]["ticket_delivery_method"]
            | null
          holder_membership_number?: string | null
          holder_name: string
          id?: string
          payment_amount_cents?: number | null
          payment_status?: Database["public"]["Enums"]["payment_status"]
          payment_status_changed_at?: string | null
          pickup_at?: string | null
          pickup_location?: string | null
          requested_by: string
          round_id: string
          status?: Database["public"]["Enums"]["ticket_status"]
          status_changed_at?: string
          ticket_file_path?: string | null
          ticket_file_uploaded_at?: string | null
        }
        Update: {
          category_id?: string
          club_id?: string
          created_at?: string
          delivery_method?:
            | Database["public"]["Enums"]["ticket_delivery_method"]
            | null
          holder_membership_number?: string | null
          holder_name?: string
          id?: string
          payment_amount_cents?: number | null
          payment_status?: Database["public"]["Enums"]["payment_status"]
          payment_status_changed_at?: string | null
          pickup_at?: string | null
          pickup_location?: string | null
          requested_by?: string
          round_id?: string
          status?: Database["public"]["Enums"]["ticket_status"]
          status_changed_at?: string
          ticket_file_path?: string | null
          ticket_file_uploaded_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ticket_requests_category_id_round_id_fkey"
            columns: ["category_id", "round_id"]
            isOneToOne: false
            referencedRelation: "ticket_categories"
            referencedColumns: ["id", "round_id"]
          },
          {
            foreignKeyName: "ticket_requests_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ticket_requests_round_id_club_id_fkey"
            columns: ["round_id", "club_id"]
            isOneToOne: false
            referencedRelation: "ticket_rounds"
            referencedColumns: ["id", "club_id"]
          },
        ]
      }
      ticket_rounds: {
        Row: {
          away_game_id: string
          closed_at: string | null
          club_id: string
          created_at: string
          created_by: string | null
          download_requires_payment: boolean
          id: string
          max_tickets_per_member: number | null
          membership_number_required: boolean
          notes: string | null
          request_deadline: string | null
        }
        Insert: {
          away_game_id: string
          closed_at?: string | null
          club_id: string
          created_at?: string
          created_by?: string | null
          download_requires_payment?: boolean
          id?: string
          max_tickets_per_member?: number | null
          membership_number_required?: boolean
          notes?: string | null
          request_deadline?: string | null
        }
        Update: {
          away_game_id?: string
          closed_at?: string | null
          club_id?: string
          created_at?: string
          created_by?: string | null
          download_requires_payment?: boolean
          id?: string
          max_tickets_per_member?: number | null
          membership_number_required?: boolean
          notes?: string | null
          request_deadline?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ticket_rounds_away_game_id_club_id_fkey"
            columns: ["away_game_id", "club_id"]
            isOneToOne: false
            referencedRelation: "away_games"
            referencedColumns: ["id", "club_id"]
          },
          {
            foreignKeyName: "ticket_rounds_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ticket_rounds_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      trip_registrations: {
        Row: {
          club_id: string
          created_at: string
          id: string
          payment_amount_cents: number | null
          payment_status: Database["public"]["Enums"]["payment_status"]
          payment_status_changed_at: string | null
          status: Database["public"]["Enums"]["registration_status"]
          status_changed_at: string
          trip_id: string
          user_id: string
        }
        Insert: {
          club_id: string
          created_at?: string
          id?: string
          payment_amount_cents?: number | null
          payment_status?: Database["public"]["Enums"]["payment_status"]
          payment_status_changed_at?: string | null
          status: Database["public"]["Enums"]["registration_status"]
          status_changed_at?: string
          trip_id: string
          user_id: string
        }
        Update: {
          club_id?: string
          created_at?: string
          id?: string
          payment_amount_cents?: number | null
          payment_status?: Database["public"]["Enums"]["payment_status"]
          payment_status_changed_at?: string | null
          status?: Database["public"]["Enums"]["registration_status"]
          status_changed_at?: string
          trip_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "trip_registrations_trip_id_club_id_fkey"
            columns: ["trip_id", "club_id"]
            isOneToOne: false
            referencedRelation: "trips"
            referencedColumns: ["id", "club_id"]
          },
          {
            foreignKeyName: "trip_registrations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      trips: {
        Row: {
          away_game_id: string
          capacity: number | null
          club_id: string
          created_at: string
          created_by: string | null
          departure_at: string | null
          id: string
          meeting_point: string | null
          notes: string | null
          price_cents: number | null
          registration_deadline: string | null
          title: string | null
          transport: Database["public"]["Enums"]["transport_mode"]
        }
        Insert: {
          away_game_id: string
          capacity?: number | null
          club_id: string
          created_at?: string
          created_by?: string | null
          departure_at?: string | null
          id?: string
          meeting_point?: string | null
          notes?: string | null
          price_cents?: number | null
          registration_deadline?: string | null
          title?: string | null
          transport: Database["public"]["Enums"]["transport_mode"]
        }
        Update: {
          away_game_id?: string
          capacity?: number | null
          club_id?: string
          created_at?: string
          created_by?: string | null
          departure_at?: string | null
          id?: string
          meeting_point?: string | null
          notes?: string | null
          price_cents?: number | null
          registration_deadline?: string | null
          title?: string | null
          transport?: Database["public"]["Enums"]["transport_mode"]
        }
        Relationships: [
          {
            foreignKeyName: "trips_away_game_id_club_id_fkey"
            columns: ["away_game_id", "club_id"]
            isOneToOne: false
            referencedRelation: "away_games"
            referencedColumns: ["id", "club_id"]
          },
          {
            foreignKeyName: "trips_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trips_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      attach_ticket_file: { Args: { p_request_id: string }; Returns: string }
      auto_allocate_tickets: {
        Args: { p_category_id: string }
        Returns: {
          allocated: number
          waitlisted: number
        }[]
      }
      cancel_ticket_request: {
        Args: { p_request_id: string }
        Returns: undefined
      }
      cancel_trip_registration: {
        Args: { p_registration_id: string }
        Returns: undefined
      }
      claim_notifications: {
        Args: { p_limit: number }
        Returns: {
          attempts: number
          body: string
          claimed_at: string | null
          club_id: string | null
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["notification_kind"]
          last_error: string | null
          sent_at: string | null
          status: Database["public"]["Enums"]["notification_status"]
          title: string
          url: string
          user_id: string
        }[]
        SetofOptions: {
          from: "*"
          to: "notifications"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      club_deletion_summary: {
        Args: { p_club_id: string }
        Returns: {
          members: number
          open_payments: number
          ticket_files: number
          ticket_rounds: number
          trips: number
        }[]
      }
      complete_notifications: {
        Args: { p_error: string; p_ids: string[]; p_success: boolean }
        Returns: undefined
      }
      confirm_all_trip_registrations: {
        Args: { p_trip_id: string }
        Returns: number
      }
      confirm_trip_registration: {
        Args: { p_registration_id: string }
        Returns: undefined
      }
      create_club: { Args: { p_name: string }; Returns: string }
      delete_push_subscription: {
        Args: { p_endpoint: string }
        Returns: undefined
      }
      detach_ticket_file: { Args: { p_request_id: string }; Returns: string }
      ensure_away_game: {
        Args: {
          p_club_id: string
          p_kickoff_at: string
          p_league_shortcut: string
          p_matchday: number
          p_openligadb_match_id: number
          p_opponent_name: string
          p_season: number
        }
        Returns: string
      }
      get_invite: {
        Args: { p_token: string }
        Returns: {
          club_id: string
          club_name: string
          is_member: boolean
        }[]
      }
      get_trip_stats: {
        Args: { p_club_id: string }
        Returns: {
          my_payment_status: Database["public"]["Enums"]["payment_status"]
          my_registration_id: string
          my_status: Database["public"]["Enums"]["registration_status"]
          my_waitlist_position: number
          taken_seats: number
          trip_id: string
          waitlist_count: number
        }[]
      }
      join_club: { Args: { p_token: string }; Returns: string }
      notification_recipients: {
        Args: { p_user_ids: string[] }
        Returns: {
          display_name: string
          email: string
          email_notifications: boolean
          user_id: string
        }[]
      }
      purge_away_game_ticket_data: {
        Args: { p_away_game_id: string; p_kickoff_at: string }
        Returns: number
      }
      regenerate_invite: { Args: { p_club_id: string }; Returns: string }
      register_for_trip: {
        Args: { p_trip_id: string }
        Returns: Database["public"]["Enums"]["registration_status"]
      }
      report_payment: {
        Args: {
          p_ticket_request_ids?: string[]
          p_trip_registration_ids?: string[]
        }
        Returns: number
      }
      request_ticket: {
        Args: {
          p_category_id: string
          p_holder_name: string
          p_membership_number: string
        }
        Returns: string
      }
      save_push_subscription: {
        Args: {
          p_auth: string
          p_endpoint: string
          p_p256dh: string
          p_user_agent: string
        }
        Returns: undefined
      }
      set_payment_status: {
        Args: {
          p_status: Database["public"]["Enums"]["payment_status"]
          p_ticket_request_ids?: string[]
          p_trip_registration_ids?: string[]
        }
        Returns: number
      }
      set_ticket_delivery: {
        Args: {
          p_method: Database["public"]["Enums"]["ticket_delivery_method"]
          p_pickup_at: string
          p_pickup_location: string
          p_request_ids: string[]
        }
        Returns: string[]
      }
      set_ticket_request_status: {
        Args: {
          p_request_id: string
          p_status: Database["public"]["Enums"]["ticket_status"]
        }
        Returns: undefined
      }
      update_ticket_request_holder: {
        Args: {
          p_holder_name: string
          p_membership_number: string
          p_request_id: string
        }
        Returns: undefined
      }
    }
    Enums: {
      club_role: "organizer" | "member"
      notification_kind:
        | "kickoff_scheduled"
        | "kickoff_changed"
        | "waitlist_promoted"
        | "ticket_allocated"
        | "ticket_rejected"
        | "ticket_delivery"
        | "trip_created"
        | "ticket_round_opened"
      notification_status: "pending" | "sending" | "sent" | "failed"
      payment_status: "open" | "reported" | "confirmed" | "refunded"
      registration_status: "requested" | "confirmed" | "waitlist" | "cancelled"
      ticket_delivery_method: "pickup" | "box_office" | "digital"
      ticket_status:
        | "requested"
        | "allocated"
        | "waitlist"
        | "rejected"
        | "cancelled"
      transport_mode: "bus" | "train" | "car"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      club_role: ["organizer", "member"],
      notification_kind: [
        "kickoff_scheduled",
        "kickoff_changed",
        "waitlist_promoted",
        "ticket_allocated",
        "ticket_rejected",
        "ticket_delivery",
        "trip_created",
        "ticket_round_opened",
      ],
      notification_status: ["pending", "sending", "sent", "failed"],
      payment_status: ["open", "reported", "confirmed", "refunded"],
      registration_status: ["requested", "confirmed", "waitlist", "cancelled"],
      ticket_delivery_method: ["pickup", "box_office", "digital"],
      ticket_status: [
        "requested",
        "allocated",
        "waitlist",
        "rejected",
        "cancelled",
      ],
      transport_mode: ["bus", "train", "car"],
    },
  },
} as const
