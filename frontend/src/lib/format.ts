import { formatUnits, parseUnits } from "viem";

export const MONTH = 30n * 24n * 60n * 60n;

export const perMonth = (flowRate: bigint) => flowRate * MONTH;
export const flowRateFromMonthly = (amount: string, decimals = 18) => parseUnits(amount || "0", decimals) / MONTH;

/// Rounds for display: 4 significant digits below 1, `digits` decimals above.
export function fmt(amount: bigint, decimals = 18, digits = 4) {
  const n = Number(formatUnits(amount, decimals));
  return n.toLocaleString("en-US", n >= 1 ? { maximumFractionDigits: digits } : { maximumSignificantDigits: 4 });
}

/// How long `balance` lasts at a net outflow of `outflow` per second, e.g. "3 months", "12 days", "5 hours".
export function runway(balance: bigint, outflow: bigint) {
  if (outflow <= 0n) return undefined;
  const secs = balance / outflow;
  const units: [bigint, string][] = [
    [MONTH, "month"],
    [24n * 3600n, "day"],
    [3600n, "hour"],
  ];
  for (const [len, name] of units) {
    const n = secs / len;
    if (n >= 1n || len === 3600n) return `${n} ${name}${n === 1n ? "" : "s"}`;
  }
}

export const short = (addr: string) => `${addr.slice(0, 6)}…${addr.slice(-4)}`;

export function errMsg(e: unknown) {
  const err = e as { shortMessage?: string; message?: string };
  return err.shortMessage ?? err.message ?? String(e);
}
