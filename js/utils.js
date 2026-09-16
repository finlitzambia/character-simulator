// js/utils.js
// Shared formatters used across dashboard, trade, ventures, debts, history.

function fmtKwacha(amount) {
  const n = Number(amount) || 0;
  const sign = n < 0 ? '-' : '';
  return sign + 'K ' + Math.abs(n).toLocaleString('en-ZM', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  });
}

function fmtPct(n) {
  const v = Number(n) || 0;
  const sign = v > 0 ? '+' : '';
  return sign + v.toFixed(1) + '%';
}

function fmtDate(isoString) {
  return new Date(isoString).toLocaleDateString('en-ZM', {
    day: 'numeric', month: 'short', year: 'numeric'
  });
}

function fmtDateTime(isoString) {
  return new Date(isoString).toLocaleString('en-ZM', {
    day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit'
  });
}

// Reputation score (0–100) -> a plain-language label, since the raw
// number means little to a learner on its own.
function reputationLabel(score) {
  if (score >= 80) return 'Disciplined';
  if (score >= 60) return 'Steady';
  if (score >= 40) return 'Building habits';
  if (score >= 20) return 'Inconsistent';
  return 'High risk';
}
