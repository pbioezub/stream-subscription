import { useState } from "react";
import { isAddress, parseEther, parseEventLogs, type Address } from "viem";
import { useAccount, useChainId, useReadContract } from "wagmi";
import { streamSubscriptionFactoryAbi } from "../abi/StreamSubscriptionFactory";
import { superTokenAbi } from "../abi/superfluid";
import { CHAINS } from "../lib/chains";
import { flowRateFromMonthly, short } from "../lib/format";
import { useTx } from "../lib/useTx";
import { Wrap } from "../components/Wrap";

export function Create() {
  const chainId = useChainId();
  const { address } = useAccount();
  const factory = CHAINS[chainId]?.factory;

  if (!address) return <p>Connect a wallet to create a subscription.</p>;
  if (!factory) return <p className="error">No factory deployed on this network yet.</p>;
  return (
    <>
      <CreateForm factory={factory} ethx={CHAINS[chainId].ethx} />
      <MySubscriptions factory={factory} owner={address} />
    </>
  );
}

function CreateForm({ factory, ethx }: { factory: Address; ethx: Address }) {
  const [token, setToken] = useState<string>(ethx);
  const [price, setPrice] = useState("0.001");
  const [share, setShare] = useState("80");
  const [reserve, setReserve] = useState("0.0001");
  const tx = useTx();

  const symbol = useReadContract({
    address: isAddress(token) ? token : undefined,
    abi: superTokenAbi,
    functionName: "symbol",
  });

  const minFlowRate = flowRateFromMonthly(price);
  const shareBps = BigInt(Math.round(Number(share) * 100));
  const valid = isAddress(token) && symbol.data && minFlowRate > 0n && shareBps >= 0n && shareBps <= 10_000n;

  async function create() {
    const reserveAmount = parseEther(reserve || "0");
    if (reserveAmount > 0n) {
      const ok = await tx.send("approving reserve", {
        address: token as Address,
        abi: superTokenAbi,
        functionName: "approve",
        args: [factory, reserveAmount],
      });
      if (!ok) return;
    }
    const receipt = await tx.send("creating", {
      address: factory,
      abi: streamSubscriptionFactoryAbi,
      functionName: "create",
      args: [token as Address, minFlowRate, shareBps, reserveAmount],
    });
    if (!receipt) return;
    const [created] = parseEventLogs({
      abi: streamSubscriptionFactoryAbi,
      eventName: "SubscriptionCreated",
      logs: receipt.logs,
    });
    window.location.hash = `#/manage/${created.args.subscription}`;
  }

  return (
    <section>
      <h2>New subscription</h2>
      <label>
        Super Token
        <input value={token} onChange={(e) => setToken(e.target.value.trim())} />
        <span className="muted small">{symbol.data ?? (isAddress(token) ? "not a super token?" : "")}</span>
      </label>
      <label>
        Price per month
        <input inputMode="decimal" value={price} onChange={(e) => setPrice(e.target.value)} />
      </label>
      <label>
        Share streamed to collaborators, %
        <input inputMode="decimal" value={share} onChange={(e) => setShare(e.target.value)} />
        <span className="muted small">the rest stays in the contract for you to withdraw</span>
      </label>
      <label>
        Reserve
        <input inputMode="decimal" value={reserve} onChange={(e) => setReserve(e.target.value)} />
        <span className="muted small">
          covers the Superfluid deposit for the outgoing stream to collaborators. You can top it up later.
        </span>
      </label>
      <button onClick={create} disabled={!valid || !!tx.pending}>
        {tx.pending ?? "create"}
      </button>
      {tx.error && <p className="error">{tx.error}</p>}
      {isAddress(token) && symbol.data && <Wrap token={token} symbol={symbol.data} />}
    </section>
  );
}

function MySubscriptions({ factory, owner }: { factory: Address; owner: Address }) {
  const { data } = useReadContract({
    address: factory,
    abi: streamSubscriptionFactoryAbi,
    functionName: "subscriptionsOf",
    args: [owner],
  });
  if (!data?.length) return null;
  return (
    <section>
      <h3>Your subscriptions</h3>
      <ul>
        {data.map((s) => (
          <li key={s}>
            <a href={`#/manage/${s}`}>{short(s)}</a>
          </li>
        ))}
      </ul>
    </section>
  );
}
