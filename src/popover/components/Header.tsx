import { formatCost, formatPercent, formatTokens, todayLabel } from '../format.js';
import type { TodaySummary } from '../types.js';
import { ClockIcon, RefreshIcon } from './icons.js';

interface HeaderProps {
  summary: TodaySummary | null;
  cacheRate: number;
  refreshing: boolean;
  onRefresh: () => void;
}

export function Header({ summary, cacheRate, refreshing, onRefresh }: HeaderProps) {
  return (
    <div className="header">
      <div className="header-left">
        <div className="tokens mono-num">
          {summary && summary.tokens > 0 ? formatTokens(summary.tokens) : '—'}
        </div>
        <div className="header-meta">
          <span>Today · {todayLabel()}</span>
          <button
            type="button"
            className="refresh-btn"
            onClick={onRefresh}
            disabled={refreshing}
            title={refreshing ? 'Refreshing usage data…' : 'Refresh usage data'}
          >
            {refreshing ? <span className="spinner" /> : <RefreshIcon />}
          </button>
        </div>
      </div>
      <div className="header-right">
        <div className="cost mono-num">{summary ? formatCost(summary.cost) : '—'}</div>
        <div className="cache-badge mono-num">
          <ClockIcon />
          cache {formatPercent(cacheRate)}
        </div>
      </div>
    </div>
  );
}