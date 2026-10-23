import { zeroAddress, type Address } from "viem";
import { useAccount, useReadContracts } from "wagmi";
import { streamSubscriptionAbi } from "../abi/StreamSubscription";
import { cfaForwarderAbi, superTokenAbi } from "../abi/superfluid";
import { CFA_FORWARDER } from "../lib/chains";
import { Wrap } from "../components/Wrap";
import { fmt, perMonth, runway, short } from "../lib/format";
import { useTx } from "../lib/useTx";

export function Subscribe({ app }: { app: Address }) {
  const base = { address: app, abi: streamSubscriptionAbi } as const;
  const info = useReadContracts({
    allowFailure: false,
    contracts: [
      { ...base, functionName: "token" },
      { ...base, functionName: "minFlowRate" },
      { ...base, functionName: "subscriberCount" },
      { ...base, functionName: "paused" },
    ],
  });

  if (info.isLoading) return <p>loading…</p>;
  if (info.error || !info.data) return <p className="error">No subscription at {short(app)} on this network.</p>;
  const [token, minFlowRate, subscriberCount, paused] = info.data;
  return <SubscribeView app={app} token={token} minFlowRate={minFlowRate} count={subscriberCount} paused={paused} />;
}

function SubscribeView(props: { app: Address; token: Address; minFlowRate: bigint; count: bigint; paused: boolean }) {
  const { app, token, minFlowRate, count, paused } = props;
  const { address } = useAccount();
  const user = address ?? zeroAddress;
  const tx = useTx();

  const tok = { address: token, abi: superTokenAbi } as const;
  const sub = { address: app, abi: streamSubscriptionAbi } as const;
  const reads = useReadContracts({
    allowFailure: false,
    contracts: [
      { ...tok, functionName: "symbol" },
      { ...tok, functionName: "decimals" },
      { ...tok, functionName: "balanceOf", args: [user] },
      { ...sub, functionName: "subscriberFlowRate", args: [user] },
      { ...sub, functionName: "bufferShortfall", args: [minFlowRate] },
      { address: CFA_FORWARDER, abi: cfaForwarderAbi, functionName: "getAccountFlowrate", args: [token, user] },
    ],
  });
  if (!reads.data) return <p>loading…</p>;
  const [symbol, decimals, balance, myRate, shortfall, netFlow] = reads.data;
  const subscribed = myRate >= minFlowRate;
  // other CFA streams of the user count too, GDA ones aren't included
  const lasts = runway(balance, subscribed ? -netFlow : minFlowRate - netFlow);

  const setFlow = (rate: bigint, label: string) =>
    tx.send(label, {
      address: CFA_FORWARDER,
      abi: cfaForwarderAbi,
      functionName: "setFlowrate",
      args: [token, app, rate],
    });

  return (
    <section>
      <h2>
        {fmt(perMonth(minFlowRate), decimals)} {symbol} / month
      </h2>
      <p className="muted">
        {count.toString()} subscriber{count === 1n ? "" : "s"} · paid as a stream, cancel any time
      </p>

      {!address ? (
        <p>Connect a wallet to subscribe.</p>
      ) : subscribed ? (
        <div className="card ok">
          <p>
            You're subscribed, streaming {fmt(perMonth(myRate), decimals)} {symbol} / month.
          </p>
          {lasts && (
            <p className="muted">
              Your balance of {fmt(balance, decimals)} {symbol} lasts about {lasts} at this rate.
            </p>
          )}
          <button onClick={() => setFlow(0n, "cancelling")} disabled={!!tx.pending}>
            {tx.pending ?? "cancel subscription"}
          </button>
        </div>
      ) : (
        <div className="card">
          <p>
            Your balance: {fmt(balance, decimals)} {symbol}
            {balance > 0n && lasts && <span className="muted"> · enough for about {lasts}</span>}
          </p>
          {paused && <p className="error">The creator has paused new subscriptions.</p>}
          {shortfall > 0n && !paused && (
            <p className="error">The creator needs to top up the reserve before new subscribers can join.</p>
          )}
          <button
            onClick={() => setFlow(minFlowRate, "subscribing")}
            disabled={!!tx.pending || paused || shortfall > 0n || balance === 0n}
          >
            {tx.pending ?? "subscribe"}
          </button>
          <p className="muted small">
            Superfluid locks a small deposit (a few hours of the stream) while it's open and returns it when you
            cancel. If your balance runs out the stream is closed automatically.
          </p>
        </div>
      )}
      {tx.error && <p className="error">{tx.error}</p>}
      {address && <Wrap token={token} symbol={symbol} />}
    </section>
  );
}
