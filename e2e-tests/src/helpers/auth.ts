import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';

// Ensure environment variables are loaded
dotenv.config({ path: path.resolve(__dirname, '../../../saloon-mostafa/.env') });

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('Supabase URL or Anon Key is missing in environment.');
}

const supabasePub = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  }
});

/**
 * Performs programmatic login, extracts the session, and constructs the
 * serialized session cookie expected by @supabase/ssr.
 */
export async function getAuthCookie(email: string, password: string): Promise<string> {
  const { data, error } = await supabasePub.auth.signInWithPassword({
    email,
    password,
  });

  if (error || !data.session) {
    throw new Error(`Supabase Auth login failed: ${error?.message || 'No session'}`);
  }

  // Supabase SSR serializes the session as a base64url-encoded JSON string prefixed with "base64-"
  const projectRef = 'havgzkklfiengdxsyqmf';
  const sessionStr = JSON.stringify(data.session);
  const base64 = Buffer.from(sessionStr, 'utf-8').toString('base64');
  const base64Url = base64
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');

  const cookieValue = `base64-${base64Url}`;

  return `sb-${projectRef}-auth-token=${cookieValue}`;
}
