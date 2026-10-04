// js/story-client.js
// Talks to the story engine (Postgres functions) and shows scenarios.
// Include AFTER supabase-client.js and utils.js on every simulator page.
//
// Page hooks (all optional):
//   <body data-guard="trade">        redirect home if that feature is still locked
//   <a data-feature="debts" ...>     greyed out + padlock while locked
//   StoryClient.refresh()            call after the learner does something that
//                                    might unlock a feature (e.g. logging venture income)
//
// Lesson bridge: opening any simulator page with ?lesson=1-2 reports that lesson
// as completed (works through login, the param is kept).

const StoryClient = (function () {
  const CHARS = { inner_voice: '💭', ba_grace: '👩🏾', kunda: '🧑🏾', mr_daka: '👨🏾‍💼', chola: '😏' };
  const FEATURE_NAMES = { trade: 'Trade', debts: 'Debts', ventures: 'Ventures' };
  const HINTS = {
    trade: 'Run your first venture activity, or finish Basics of Investing, to unlock Trade.',
    debts: 'Finish Credit & Debt on the lessons site, or keep playing, to unlock Debts.'
  };
  let features = null;
  let yungsta = 'your yungsta';
  let avatarEmoji = '';
  let lastNeglect = null;
  let queue = [];
  let busy = false;
  let started = false;

  function money(n) { return typeof fmtKwacha === 'function' ? fmtKwacha(n) : 'K ' + Number(n).toFixed(2); }
  function esc(s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

  function injectUi() {
    if (document.getElementById('story-css')) return;
    const css = document.createElement('style');
    css.id = 'story-css';
    css.textContent = `
      .story-locked{opacity:.55;position:relative}
      .story-locked::after{content:"🔒";position:absolute;top:10px;right:12px;font-size:16px}
      #story-banner{position:fixed;left:10px;right:10px;bottom:12px;z-index:1500;background:#7A1010;color:#fff;border-radius:14px;
        padding:11px 13px;display:flex;gap:10px;align-items:center;font:600 12.5px/1.35 'DM Sans',system-ui,sans-serif;box-shadow:0 8px 24px rgba(0,0,0,.25)}
      #story-banner span{flex:1}
      #story-banner button{border:0;border-radius:10px;padding:8px 11px;font:700 12px inherit;font-family:inherit;cursor:pointer;background:#fff;color:#7A1010}
      #story-banner button.ghost{background:transparent;color:#fff;border:1px solid rgba(255,255,255,.5)}
      body.has-banner{padding-bottom:78px}
      #story-toast{position:fixed;left:50%;top:16px;transform:translate(-50%,-40px);background:#14532D;color:#fff;
        padding:12px 18px;border-radius:14px;font:600 13px/1.4 'DM Sans',system-ui,sans-serif;max-width:88vw;text-align:center;
        z-index:3000;opacity:0;transition:all .3s;pointer-events:none}
      #story-toast.on{opacity:1;transform:translate(-50%,0)}
      #story-bd{position:fixed;inset:0;background:rgba(17,24,39,.55);z-index:2000;display:none}
      #story-card{position:fixed;left:0;right:0;bottom:0;z-index:2001;background:#fff;border-radius:22px 22px 0 0;
        padding:22px 20px calc(24px + env(safe-area-inset-bottom,0px));max-width:640px;margin:0 auto;max-height:90vh;overflow:auto;
        transform:translateY(105%);transition:transform .35s;font-family:'DM Sans',system-ui,sans-serif;color:#111827}
      body.story-on #story-bd{display:block}
      body.story-on #story-card{transform:none}
      #story-card .sc-top{display:flex;align-items:center;gap:12px;margin-bottom:12px}
      #story-card .sc-ch{width:46px;height:46px;border-radius:50%;background:#F0FDF4;display:flex;align-items:center;justify-content:center;font-size:24px;flex:none}
      #story-card .sc-k{font-size:11px;font-weight:800;letter-spacing:.1em;color:#15803D}
      #story-card h2{font-size:18px;font-weight:800;line-height:1.25;margin:2px 0 0}
      #story-card .sc-intro{font-size:13px;color:#6B7280;margin:0 0 10px;font-style:italic;line-height:1.5}
      #story-card .sc-body{font-size:15px;line-height:1.6;margin:0 0 16px}
      #story-card .sc-ch-btn{display:block;width:100%;text-align:left;padding:14px 16px;margin-bottom:10px;border:2px solid #E5E7EB;
        border-radius:14px;background:#fff;font-weight:700;font-size:14.5px;line-height:1.35;font-family:inherit;color:#111827;cursor:pointer}
      #story-card .sc-ch-btn:active{background:#F0FDF4;border-color:#22C55E}
      #story-card .sc-go{display:block;width:100%;padding:14px;border:0;border-radius:14px;background:#15803D;color:#fff;
        font-weight:800;font-size:15px;font-family:inherit;cursor:pointer;box-shadow:0 4px 0 #14532D}
      #story-card .sc-err{background:#FEF2F2;color:#7A1010;border-radius:10px;padding:10px 12px;font-size:13px;margin-bottom:12px}
      #story-card .sc-chip{display:inline-block;margin:0 8px 12px 0;padding:5px 11px;border-radius:99px;font:700 12.5px inherit;font-family:inherit}
      #story-card .sc-chip.up{background:#DCFCE7;color:#14532D}
      #story-card .sc-chip.down{background:#FEE2E2;color:#7A1010}
    `;
    document.head.appendChild(css);
    const bd = document.createElement('div'); bd.id = 'story-bd';
    const card = document.createElement('div'); card.id = 'story-card';
    const toast = document.createElement('div'); toast.id = 'story-toast';
    document.body.appendChild(bd); document.body.appendChild(card); document.body.appendChild(toast);
  }

  let toastTimer = null;
  function toast(msg) {
    injectUi();
    const t = document.getElementById('story-toast');
    t.textContent = msg; t.classList.add('on');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('on'), 4200);
  }

  function applyFeatures() {
    if (!features) return;
    document.querySelectorAll('[data-feature]').forEach(el => {
      const f = el.getAttribute('data-feature');
      if (features[f] === false) {
        el.classList.add('story-locked');
        if (!el.__storyBound) {
          el.addEventListener('click', ev => {
            if (features[f] === false) { ev.preventDefault(); toast(HINTS[f] || 'Locked for now.'); }
          });
          el.__storyBound = true;
        }
      } else {
        el.classList.remove('story-locked');
      }
    });
    const guard = document.body && document.body.getAttribute('data-guard');
    if (guard && features[guard] === false) {
      window.location.replace('index.html?locked=' + encodeURIComponent(guard));
    }
  }

  function closeCard() { document.body.classList.remove('story-on'); }

  function renderChoices(pendingId, node, header) {
    const card = document.getElementById('story-card');
    const choices = (node.choices || []).map(c =>
      `<button class="sc-ch-btn" data-i="${c.index}">${esc(c.label)}</button>`).join('');
    card.innerHTML = header + `<div class="sc-body">${esc(node.body)}</div><div id="sc-err"></div>${choices}`;
    card.querySelectorAll('.sc-ch-btn').forEach(b => {
      b.addEventListener('click', () => choose(pendingId, Number(b.getAttribute('data-i')), header, b.textContent));
    });
  }

  function headerHtml(ev, withIntro) {
    return `<div class="sc-top"><div class="sc-ch">${CHARS[ev.character] || '📖'}</div>
      <div><div class="sc-k">${esc(yungsta.toUpperCase())} NEEDS YOUR ADVICE</div><h2>${esc(ev.title || 'Something happened')}</h2></div></div>` +
      (withIntro && ev.intro ? `<p class="sc-intro">${esc(ev.intro)}</p>` : '');
  }

  function showEvent(ev) {
    injectUi();
    const header = headerHtml(ev, true);
    renderChoices(ev.pending_id, ev, header);
    document.body.classList.add('story-on');
  }

  async function choose(pendingId, index, header, label) {
    if (busy) return; busy = true;
    const card = document.getElementById('story-card');
    const { data, error } = await supabase.rpc('story_choose', { p_pending_id: pendingId, p_choice_index: index });
    busy = false;
    if (error || !data || (data.error && data.error !== 'insufficient_cash')) {
      document.getElementById('sc-err').innerHTML = '<div class="sc-err">Something went wrong. Please try again.</div>';
      return;
    }
    if (data.error === 'insufficient_cash') {
      document.getElementById('sc-err').innerHTML = '<div class="sc-err">You need ' + money(data.needed) +
        ' but only have ' + money(data.cash) + '. Earn or sell something first, or choose the other option.</div>';
      return;
    }
    let chips = '';
    if (data.done) {
      const cd = Number(data.cash_delta || 0), rd = Number(data.reputation_delta || 0);
      if (cd) chips += `<span class="sc-chip ${cd > 0 ? 'up' : 'down'}">Cash ${cd > 0 ? '+' : ''}${money(cd)}</span>`;
      const bd = Number(data.business_delta || 0);
      if (bd) chips += `<span class="sc-chip ${bd > 0 ? 'up' : 'down'}">Business ${bd > 0 ? '+' : ''}${money(bd)}</span>`;
      if (rd) chips += `<span class="sc-chip ${rd > 0 ? 'up' : 'down'}">Reputation ${rd > 0 ? '+' : ''}${rd}</span>`;
      (data.unlocked || []).forEach(f => { chips += `<span class="sc-chip up">${FEATURE_NAMES[f] || f} unlocked 🎉</span>`; });
    }
    card.innerHTML = header +
      `<div class="sc-body">${esc(data.narrative || '')}</div>${chips ? '<div>' + chips + '</div>' : ''}` +
      `<button class="sc-go" id="sc-next">Continue</button>`;
    document.getElementById('sc-next').addEventListener('click', () => {
      if (!data.done && data.node) { renderChoices(pendingId, data.node, header); return; }
      if (data.done) { showTeachBack(pendingId, header, label); return; }
      closeCard();
      setTimeout(() => window.location.reload(), 250);
    });
  }

  // Daily check-in reminder: a day with no guidance means the yungsta makes costly mistakes
  function renderBanner(n) {
    const old = document.getElementById('story-banner'); if (old) old.remove();
    document.body.classList.remove('has-banner');
    if (!n || !n.active || n.guided_today || n.paused) return;
    const b = document.createElement('div'); b.id = 'story-banner';
    b.innerHTML = `<span>${esc(yungsta)} needs a check-in today. Skip it and they will make costly mistakes.</span>` +
      `<button id="sb-check">Check in</button>` + (n.can_pause ? `<button class="ghost" id="sb-pause">Pause ${n.pause_days}d</button>` : '');
    document.body.appendChild(b); document.body.classList.add('has-banner');
    document.getElementById('sb-check').addEventListener('click', async () => {
      const d = await check({ silent: true });
      if (d && !(d.question || (d.events || []).length || (d.blunders || []).length)) toast('Finish a lesson, then come back to check in.');
    });
    const p = document.getElementById('sb-pause');
    if (p) p.addEventListener('click', async () => {
      const { data } = await supabase.rpc('yungsta_pause', { p_days: n.pause_days });
      if (data && data.ok) { toast(yungsta + ' is safe for ' + data.days + ' days.'); renderBanner(null); }
      else toast('You can pause once every two weeks.');
    });
  }

  function blunderHead() {
    return `<div class="sc-top"><div class="sc-ch">${avatarEmoji || '🧒'}</div>
      <div><div class="sc-k">WHILE YOU WERE AWAY</div><h2></h2></div></div>`;
  }
  function showBlunders(items) {
    injectUi();
    const card = document.getElementById('story-card');
    const total = items.reduce((s, i) => s + Number(i.amount), 0);
    card.innerHTML = blunderHead().replace('<h2></h2>', `<h2>${esc(yungsta)} made ${items.length === 1 ? 'a costly mistake' : items.length + ' costly mistakes'}</h2>`) +
      items.map(i => `<div class="sc-body"><b>${esc(i.title)}</b><br>${esc(i.story)}<br><span class="sc-chip down" style="margin-top:6px">-${money(i.amount)}</span></div>`).join('') +
      `<div class="sc-intro">Total lost: ${money(total)}. Debrief ${esc(yungsta)} on each mistake, and a good answer wins half of it back.</div>` +
      `<button class="sc-go" id="sb-go">Debrief ${esc(yungsta)}</button>` +
      `<button class="sc-ch-btn" id="sb-skip" style="margin-top:10px;text-align:center;font-weight:600">Not now (keep the loss)</button>`;
    document.body.classList.add('story-on');
    document.getElementById('sb-go').addEventListener('click', () => debriefStep(items, 0, 0));
    document.getElementById('sb-skip').addEventListener('click', async () => {
      await supabase.rpc('yungsta_blunders_skip'); closeCard(); setTimeout(() => window.location.reload(), 250);
    });
  }
  function debriefStep(items, idx, won) {
    if (idx >= items.length) {
      const card = document.getElementById('story-card');
      card.innerHTML = blunderHead().replace('<h2></h2>', `<h2>Debrief complete</h2>`) +
        `<div class="sc-body">${won > 0 ? 'You won back ' + money(won) + ' by teaching ' + esc(yungsta) + ' what went wrong.' : 'No money won back this time, but the lesson is learned.'}</div>` +
        `<div class="sc-intro">A daily check-in keeps ${esc(yungsta)} out of trouble.</div><button class="sc-go" id="sb-done">Continue</button>`;
      document.getElementById('sb-done').addEventListener('click', () => { closeCard(); setTimeout(() => window.location.reload(), 250); });
      return;
    }
    const it = items[idx], card = document.getElementById('story-card');
    card.innerHTML = blunderHead().replace('<h2></h2>', `<h2>${esc(it.title)}</h2>`) +
      `<div class="sc-body"><b>${esc(it.question)}</b></div><div class="sc-intro">What do you teach ${esc(yungsta)}?</div><div id="sc-err"></div>` +
      it.options.map(o => `<button class="sc-ch-btn" data-i="${o.index}">${esc(o.text)}</button>`).join('');
    card.querySelectorAll('.sc-ch-btn').forEach(b => b.addEventListener('click', async () => {
      if (busy) return; busy = true;
      const { data, error } = await supabase.rpc('yungsta_debrief', { p_id: it.id, p_choice: Number(b.getAttribute('data-i')) });
      busy = false;
      if (error || !data || data.error) { document.getElementById('sc-err').innerHTML = '<div class="sc-err">Something went wrong. Please try again.</div>'; return; }
      const rec = Number(data.recovered || 0);
      card.innerHTML = blunderHead().replace('<h2></h2>', `<h2>${esc(it.title)}</h2>`) +
        `<div><span class="sc-chip ${data.correct ? 'up' : 'down'}">${data.correct ? 'Correct' : 'Not quite'}</span>${rec ? `<span class="sc-chip up">+${money(rec)} back</span>` : ''}</div>` +
        `<div class="sc-body">${data.correct ? esc(data.recovery_text || data.feedback) : `<b>The right answer:</b> ${esc(data.right_text)}<br><br>${esc(data.explanation)}`}</div>` +
        `<button class="sc-go" id="sb-next">${idx + 1 < items.length ? 'Next mistake' : 'Finish'}</button>`;
      document.getElementById('sb-next').addEventListener('click', () => debriefStep(items, idx + 1, won + rec));
    }));
  }

  // The yungsta asks the learner a question about a lesson they finished (retrieval + teaching)
  function showQuestion(q) {
    injectUi();
    const card = document.getElementById('story-card');
    const head = `<div class="sc-top"><div class="sc-ch">${avatarEmoji || '🧒'}</div>
      <div><div class="sc-k">${esc(yungsta.toUpperCase())} HAS A QUESTION</div><h2>${esc(q.topic || 'Can you help me understand?')}</h2></div></div>`;
    card.innerHTML = head + `<div class="sc-body"><b>${esc(q.question)}</b></div>
      <div class="sc-intro">What do you tell ${esc(yungsta)}?</div><div id="sc-err"></div>` +
      q.options.map(o => `<button class="sc-ch-btn" data-i="${o.index}">${esc(o.text)}</button>`).join('');
    card.querySelectorAll('.sc-ch-btn').forEach(b => b.addEventListener('click', () => answerQuestion(q, Number(b.getAttribute('data-i')), head, b.textContent)));
    document.body.classList.add('story-on');
  }

  async function answerQuestion(q, index, head, label) {
    if (busy) return; busy = true;
    const { data, error } = await supabase.rpc('yungsta_answer', { p_id: q.id, p_choice: index });
    busy = false;
    if (error || !data || data.error) {
      document.getElementById('sc-err').innerHTML = '<div class="sc-err">Something went wrong. Please try again.</div>';
      return;
    }
    const card = document.getElementById('story-card');
    const verdict = data.correct
      ? `<span class="sc-chip up">Correct</span>`
      : `<span class="sc-chip down">Not quite</span>`;
    card.innerHTML = head + `<div>${verdict}</div>
      <div class="sc-body"><i>${esc(data.reaction)}</i></div>
      <div class="sc-body">${data.correct ? esc(data.feedback) : `<b>The right answer:</b> ${esc(data.right_text)}<br><br>${esc(data.explanation)}`}</div>
      <div class="sc-intro">Say the rule out loud to ${esc(yungsta)} in your own words. ${data.returns ? esc(yungsta) + ' will check this one with you again in a couple of days.' : ''}</div>
      <button class="sc-go" id="sc-next">Continue</button>`;
    document.getElementById('sc-next').addEventListener('click', () => {
      closeCard(); setTimeout(() => window.location.reload(), 250);
    });
  }

  // "Pass it on": learning-by-teaching works best when the learner EXPLAINS, ideally out loud.
  function saveJournal(entry) {
    try {
      const k = 'fin-sim-journal', a = JSON.parse(localStorage.getItem(k) || '[]');
      a.unshift(entry); localStorage.setItem(k, JSON.stringify(a.slice(0, 40)));
    } catch (e) {}
  }
  function showTeachBack(pendingId, header, label) {
    const card = document.getElementById('story-card');
    const title = (card.querySelector('h2') || {}).textContent || '';
    card.innerHTML = header +
      `<div class="sc-body"><b>Pass it on.</b> Say it out loud to ${esc(yungsta)}: what should they remember from this, and why did you advise it? Saying it aloud is the part that helps you learn it.</div>` +
      `<textarea id="sc-note" rows="2" maxlength="280" placeholder="Optional: jot it down (stays on this phone)" style="width:100%;padding:10px 12px;border:1.5px solid #E5E7EB;border-radius:12px;font:inherit;margin-bottom:10px"></textarea>` +
      `<div class="sc-intro">And would you make the same call with your own money?</div>` +
      `<button class="sc-go" id="sc-explained">I have explained it</button>` +
      `<button class="sc-ch-btn" id="sc-skip" style="margin-top:10px;text-align:center;font-weight:600">Skip</button>`;
    const finish = async (explained) => {
      if (explained) {
        saveJournal({ t: Date.now(), event: title, choice: label || '', note: (document.getElementById('sc-note').value || '').trim() });
        try { await supabase.rpc('sim_teachback', { p_pending_id: pendingId }); } catch (e) {}
      }
      closeCard();
      setTimeout(() => window.location.reload(), 250);
    };
    document.getElementById('sc-explained').addEventListener('click', () => finish(true));
    document.getElementById('sc-skip').addEventListener('click', () => finish(false));
  }

  async function check(opts) {
    const { data, error } = await supabase.rpc('story_pending');
    if (error || !data || data.error) return null;
    features = data.features;
    if (data.yungsta) yungsta = data.yungsta;
    if (data.avatar) avatarEmoji = data.avatar;
    applyFeatures();
    if (!(opts && opts.silent) && (data.unlocked || []).length) {
      toast((data.unlocked || []).map(f => (FEATURE_NAMES[f] || f) + ' unlocked 🎉').join(' · '));
    }
    lastNeglect = data.neglect || null;
    renderBanner(lastNeglect);
    if ((data.blunders || []).length && !document.body.classList.contains('story-on')) { showBlunders(data.blunders); return data; }
    queue = data.events || [];
    if (queue.length && !document.body.classList.contains('story-on')) showEvent(queue[0]);
    else if (!queue.length && data.question && !document.body.classList.contains('story-on')) showQuestion(data.question);
    return data;
  }

  async function init() {
    if (started) return; started = true;
    if (typeof supabase === 'undefined' || !supabase.auth) return;
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return;
    injectUi();

    const params = new URLSearchParams(window.location.search);
    const lesson = params.get('lesson');
    if (lesson) {
      await supabase.rpc('story_fire_lesson', { p_lesson: lesson });
      params.delete('lesson'); params.delete('skill');
      const q = params.toString();
      window.history.replaceState({}, '', window.location.pathname + (q ? '?' + q : ''));
    }
    const locked = params.get('locked');
    if (locked && HINTS[locked]) toast(HINTS[locked]);
    await collect();
    await check();
  }

  async function collect() {
    if (typeof supabase === 'undefined' || !supabase.auth) return null;
    const { data, error } = await supabase.rpc('sim_collect_income');
    if (error || !data || data.error) return null;
    if (data.days > 0 && Number(data.revenue) > 0 && !data.events) {
      const n = Number(data.net);
      injectUi();
      toast('Your ventures ' + (n >= 0 ? 'earned ' : 'lost ') + money(Math.abs(n)) + ' over ' + data.days + (data.days === 1 ? ' day' : ' days') + '.');
    }
    if (data.events > 0) { injectUi(); toast('Something has happened at one of your ventures. A decision is waiting.'); }
    return data;
  }

  async function refresh() { return check(); }

  document.addEventListener('DOMContentLoaded', init);
  return { init, refresh, collect, toast, guard: applyFeatures };
})();

window.StoryClient = StoryClient; // const at top level is not a window property, and the pages check window.StoryClient
