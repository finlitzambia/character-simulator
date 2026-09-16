// scripts/update_prices.js
// Run manually (node scripts/update_prices.js) or on a schedule via
// GitHub Actions. Applies a small randomized daily drift to each active
// instrument's price and logs the new price into instrument_price_history.
//
// This is v1: simulated movement, not live LuSE data. It exists so a
// learner's portfolio actually moves day to day, which is the whole
// point of "continuous progression." Swap this out later for real data
// pulled from luse.co.zm/afx.kwayisi.org if/when that's worth the
// maintenance cost.

const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY; // service role, NOT the anon key — this script needs write access and should never run in the browser

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_KEY environment variables.');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

// Different instrument kinds drift at different realistic volatilities.
const DAILY_VOLATILITY = {
  share: 0.02,        // +/- up to 2% a day — LuSE shares can move meaningfully
  t_bill: 0.0005,      // near-flat, T-Bills don't swing day to day
  bond: 0.001,
  money_market: 0.0003
};

function randomDrift(kind) {
  const vol = DAILY_VOLATILITY[kind] ?? 0.01;
  // Roughly normal-ish via averaging two uniform randoms, centered on 0.
  const r = (Math.random() + Math.random() - 1);
  return r * vol;
}

async function run() {
  const { data: instruments, error } = await supabase
    .from('instruments')
    .select('*')
    .eq('is_active', true);

  if (error) {
    console.error('Failed to fetch instruments:', error.message);
    process.exit(1);
  }

  for (const ins of instruments) {
    const drift = randomDrift(ins.kind);
    const newPrice = Math.max(0.01, Number(ins.current_price) * (1 + drift));
    const rounded = Math.round(newPrice * 10000) / 10000;

    const { error: updateErr } = await supabase
      .from('instruments')
      .update({ current_price: rounded })
      .eq('id', ins.id);

    const { error: historyErr } = await supabase
      .from('instrument_price_history')
      .insert({ instrument_id: ins.id, price: rounded });

    if (updateErr || historyErr) {
      console.error(`Failed to update ${ins.ticker}:`, updateErr?.message || historyErr?.message);
    } else {
      console.log(`${ins.ticker}: ${ins.current_price} -> ${rounded}`);
    }
  }

  console.log(`Done. Updated ${instruments.length} instruments.`);
}

run();
