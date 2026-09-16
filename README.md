# FinLit Zambia — Financial Character Simulator

A standalone practice tool, separate from the Course Builder / Sandbox
login. Learners create their own account here and build a fake
"financial character" — tracking cash at hand, investments, small
business ventures, and debt over time — to practice what they're
learning in the courses without any real money involved.

This is **Tier 1 integration**: lessons in the Course Builder link out
to this app via a plain URL. There is no shared login and no automatic
data sync back into the course platform (that's a possible future
upgrade — see the note at the bottom).

## What's in this repo

| File | Purpose |
|---|---|
| `login.html` | Sign up / log in, with a "keep me logged in" persistent session |
| `index.html` | Dashboard — net worth, cash/investments/ventures/debt summary, chart |
| `trade.html` | Buy/sell instruments |
| `ventures.html` | Start a fake business, log revenue/expense events |
| `debts.html` | Take a loan, watch interest, repay |
| `history.html` | Full filterable transaction ledger |
| `js/supabase-client.js` | Shared Supabase connection + auth guard used by every page |
| `js/utils.js` | Shared formatters (kwacha, percentages, dates) |
| `db/schema.sql` | The full database schema — run this first |
| `db/seed_instruments.sql` | Starter list of tradeable instruments — run this second |
| `scripts/update_prices.js` | Drifts instrument prices daily (simulated, not live LuSE data) |
| `.github/workflows/update-prices.yml` | Runs the price script automatically once a day |

## Setup — one time only

1. **Create a Supabase project** at [supabase.com](https://supabase.com) (free tier is enough to start).
2. **Run the schema.** Open the SQL editor in your Supabase dashboard, paste in `db/schema.sql`, run it. Then do the same with `db/seed_instruments.sql`.
3. **Enable email auth.** In Supabase → Authentication → Providers, make sure Email is turned on. (You can also enable magic-link/passwordless later if you want to skip passwords entirely.)
4. **Get your API keys.** Supabase → Settings → API gives you a **Project URL** and an **anon public key**.
5. **Wire the keys in.** Open `js/supabase-client.js` and `login.html`, replace `YOUR-PROJECT.supabase.co` and `YOUR-ANON-PUBLIC-KEY` with your real values. (The anon key is safe to be public — Row Level Security in the schema is what actually locks each learner to their own data.)
6. **Deploy to GitHub Pages.** Push this repo to GitHub, then in the repo's Settings → Pages, set the source to the `main` branch root. Your app will be live at `https://yourusername.github.io/character-simulator/login.html`.

## Setup for the automatic price updates (optional, can skip for now)

If you want prices to drift daily on their own:

1. In your Supabase project, go to Settings → API and copy the **service_role** key (different from the anon key — this one has write access and must never be exposed in frontend code).
2. In your GitHub repo, go to Settings → Secrets and variables → Actions, and add two repository secrets: `SUPABASE_URL` and `SUPABASE_SERVICE_KEY`.
3. That's it — the workflow in `.github/workflows/update-prices.yml` will run automatically once a day. You can also trigger it manually anytime from the repo's Actions tab.

If you'd rather not set this up yet, prices simply stay static until you run `node scripts/update_prices.js` manually or come back to this step.

## Linking from a course lesson (Tier 1 integration)

In the Course Builder, inside a lesson's Text (HTML) content block, add
a simple link-out card, for example:

```html
<div style="background:#F0FDF4;border:1px solid #DCFCE7;border-radius:14px;padding:16px;text-align:center">
  <p style="margin-bottom:10px;font-size:13px;color:#374151">Practice what you just learned with fake money.</p>
  <a href="https://yourusername.github.io/character-simulator/login.html"
     target="_blank"
     style="display:inline-block;background:#15803D;color:#fff;padding:10px 20px;border-radius:20px;text-decoration:none;font-weight:700;font-size:13px">
    Open your Financial Character →
  </a>
</div>
```

No further setup needed on the Course Builder side — this works with
the platform exactly as it exists today.

## Possible future upgrade (Tier 2, needs backend dev access)

If you ever get access to modify the Course Builder itself, the most
valuable single addition would be a merge token (e.g. `{{learner_id}}`)
available inside lesson HTML blocks, so a link like
`...login.html?learner={{learner_id}}` could pass a real identity
through and let this app auto-create/recognise the matching character
account — removing the need for a learner to log into two separate
systems. Not required for v1; noted here so it isn't lost.

## Known limitations of this v1

- Prices are simulated, not live LuSE data.
- `avg_buy_price` on a repeat buy is simplified to "latest trade price," not a true weighted average — fine for teaching purposes, worth refining if you want precise realized-gain tracking.
- No shared login with the Course Builder (by design, Tier 1 only).
- `net_worth_snapshots` needs something to actually populate it daily — either a small Edge Function/cron job (same pattern as `update_prices.js`), or compute-on-read as `index.html` currently does as a fallback.
