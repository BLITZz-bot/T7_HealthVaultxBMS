/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_BACKEND?: string;
  readonly VITE_SUPABASE_URL?: string;
  readonly VITE_SUPABASE_ANON_KEY?: string;
  readonly VITE_DUMMY_EMAIL?: string;
  readonly VITE_DUMMY_PASSWORD?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
