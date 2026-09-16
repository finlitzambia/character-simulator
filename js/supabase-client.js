// js/supabase-client.js
// One shared Supabase client instance — every page includes this script
// FIRST, before its own page-specific script, and uses the global
// `supabase` object it creates.

const SUPABASE_URL = 'https://xzuroroziigcxctumjsr.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh6dXJvcm96aWlnY3hjdHVtanNyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk1MDA2MDgsImV4cCI6MjEwNTA3NjYwOH0.kqWBBe3nZ19Bcr5tsd8HqTNAwnY2vKTeBksFxZ--ods';

// Loaded via <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2">
// on every page before this file.
const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ── Session guard ──────────────────────────────────────────────
// Call this at the top of every page except login.html. Redirects to
// login if there's no valid session; otherwise returns the user object.
async function requireAuth() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    window.location.href = 'login.html';
    return null;
  }
  return session.user;
}

async function logOut() {
  await supabase.auth.signOut();
  window.localStorage.removeItem('finlit-sim-session');
  window.sessionStorage.removeItem('finlit-sim-session');
  window.location.href = 'login.html';
}
