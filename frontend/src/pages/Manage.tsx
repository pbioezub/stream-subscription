import { useState } from "react";
import { isAddress, parseEther, type Address } from "viem";
import { useQuery } from "@tanstack/react-query";
import { useAccount, useChainId, useReadContracts } from "wagmi";
import { streamSubscriptionAbi } from "../abi/StreamSubscription";
import { gdaForwarderAbi, superTokenAbi } from "../abi/superfluid";
import { CHAINS, GDA_FORWARDER } from "../lib/chains";
import { fmt, perMonth, short } from "../lib/format";
import { poolMembers, subscribers } from "../lib/subgraph";
import { useTx } from "../lib/useTx";

export function Manage({ app }: { app: Address }) {
  const { address } = useAccount();
  const chainId = useChainId();
  const chain = CHAINS[chainId];
  const tx = useTx();
  const [topUp, setTopUp] = useState("");

  const base = { address: app, abi: streamSubscriptionAbi } as const;
  const info = useReadContracts({
    allowFailure: false,
    query: { refetchInterval: 10_000 },
    contracts: [
      { ...base, functionName: "owner" },
      { ...base, functionName: "token" },
      { ...base, functionName: "pool" },
      { ...base, functionName: "minFlowRate" },
      { ...base, functionName: "poolShareBps" },
      { ...base, functionName: "subscriberCount" },
      { ...base, functionName: "paused" },
      { ...base, functionName: "totalInflowRate" },
      { ...base, functionName: "distributionFlowRate" },
      { ...base, functionName: "withdrawable" },
    ],
  });
  const token = info.data?.[1];
  const tokenInfo = useReadContracts({
    allowFailure: false,
    query: { enabled: !!token },
    contracts: [
      { address: token!, abi: superTokenAbi, functionName: "symbol" },
      { address: token!, abi: superTokenAbi, functionName: "decimals" },
    ],
  });
  const shortfall = useReadContracts({
    allowFailure: false,
    query: { enabled: !!info.data, refetchInterval: 10_000 },
    contracts: [{ ...base, functionName: "bufferShortfall", args: [info.data?.[3] ?? 0n] }],
  });

  if (info.isLoading) return <p>loading…</p>;
  if (info.error || !info.data) return <p className="error">No subscription at {short(app)} on this network.</p>;
  if (!tokenInfo.data || !shortfall.data) return <p>loading…</p>;

  const [owner, , pool, minFlowRate, poolShareBps, count, paused, inflow, distribution, withdrawable] = info.data;
  const [symbol, decimals] = tokenInfo.data;
  const [need] = shortfall.data;
  const isOwner = address?.toLowerCase() === owner.toLowerCase();
  const money = (v: bigint) => `${fmt(v, decimals)} ${symbol}`;
  const link = `${window.location.origin}${window.location.pathname}#/s/${app}`;

  return (
    <section>
      <h2>Subscription {short(app)}</h2>
      <p className="muted">
        {money(perMonth(minFlowRate))} / month · {Number(poolShareBps) / 100}% to collaborators ·{" "}
        <a href={`${chain?.explorer}/address/${app}`}>explorer</a>
      </p>
      <p className="small">
        Subscribe link: <a href={`#/s/${app}`}>{link}</a>
      </p>

      <div className="stats">
        <Stat label="subscribers" value={count.toString()} />
        <Stat label="revenue / month" value={money(perMonth(inflow))} />
        <Stat label="to collaborators / month" value={money(perMonth(distribution))} />
        <Stat label="withdrawable" value={money(withdrawable)} />
      </div>

      {paused && <p className="error">New subscriptions are paused.</p>}
      {need > 0n && (
        <p className="error">The reserve is {money(need)} short for the next subscriber.</p>
      )}

      {isOwner && (
        <div className="card">
          <h3>Owner</h3>
          <div className="row">
            <button
              disabled={!!tx.pending || withdrawable === 0n}
              onClick={() =>
                tx.send("withdrawing", { ...base, functionName: "withdraw", args: [address!, 2n ** 256n - 1n] })
              }
            >
              withdraw all
            </button>
            <button
              disabled={!!tx.pending}
              onClick={() =>
                tx.send(paused ? "unpausing" : "pausing", { ...base, functionName: "setPaused", args: [!paused] })
              }
            >
              {paused ? "resume new subscriptions" : "pause new subscriptions"}
            </button>
          </div>
          <div className="row">
            <input
              placeholder={need > 0n ? fmt(need, decimals, 8) : "top up reserve"}
              inputMode="decimal"
              value={topUp}
              onChange={(e) => setTopUp(e.target.value)}
            />
            <button
              disabled={!!tx.pending || !Number(topUp)}
              onClick={async () => {
                await tx.send("topping up", {
                  address: token!,
                  abi: superTokenAbi,
                  functionName: "transfer",
                  args: [app, parseEther(topUp)],
                });
                setTopUp("");
              }}
            >
              top up
            </button>
          </div>
          {tx.pending && <p className="muted">{tx.pending}…</p>}
          {tx.error && <p className="error">{tx.error}</p>}
        </div>
      )}

      {chain && <Members app={app} pool={pool} subgraph={chain.subgraph} isOwner={isOwner} />}
      {chain && <Subscribers app={app} subgraph={chain.subgraph} money={money} />}
    </section>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="stat">
      <div className="muted small">{label}</div>
      <div>{value}</div>
    </div>
  );
}

function Members({ app, pool, subgraph, isOwner }: { app: Address; pool: Address; subgraph: string; isOwner: boolean }) {
  const { address } = useAccount();
  const tx = useTx();
  const [member, setMember] = useState("");
  const [units, setUnits] = useState("1");
  const members = useQuery({ queryKey: ["members", pool], queryFn: () => poolMembers(subgraph, pool) });
  const me = useReadContracts({
    allowFailure: false,
    query: { enabled: !!address },
    contracts: [{ address: GDA_FORWARDER, abi: gdaForwarderAbi, functionName: "isMemberConnected", args: [pool, address!] }],
  });

  const list = members.data ?? [];
  const total = list.reduce((s, m) => s + BigInt(m.units), 0n);
  const amMember = list.some((m) => m.account.id === address?.toLowerCase());

  const setMemberUnits = (who: Address, u: bigint) =>
    tx.send("updating units", {
      address: app,
      abi: streamSubscriptionAbi,
      functionName: "setMemberUnits",
      args: [[who], [u]],
    });

  return (
    <div className="card">
      <h3>Collaborators</h3>
      {members.isLoading && <p className="muted">loading…</p>}
      {members.error && <p className="error">Couldn't load members from the subgraph.</p>}
      {list.length === 0 && !members.isLoading && <p className="muted">No collaborators yet — revenue stays in the contract.</p>}
      {list.length > 0 && (
        <table>
          <tbody>
            {list.map((m) => (
              <tr key={m.account.id}>
                <td>{short(m.account.id)}</td>
                <td>{m.units} units</td>
                <td>{((Number(m.units) / Number(total)) * 100).toFixed(1)}%</td>
                <td className="muted small">{m.isConnected ? "connected" : "not connected"}</td>
                {isOwner && (
                  <td>
                    <button className="link" disabled={!!tx.pending} onClick={() => setMemberUnits(m.account.id, 0n)}>
                      remove
                    </button>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <p className="muted small">The subgraph can lag a few blocks behind.</p>

      {amMember && me.data && !me.data[0] && (
        <p>
          You're a collaborator.{" "}
          <button
            disabled={!!tx.pending}
            onClick={() =>
              tx.send("connecting", { address: GDA_FORWARDER, abi: gdaForwarderAbi, functionName: "connectPool", args: [pool, "0x"] })
            }
          >
            connect to receive the stream directly
          </button>
        </p>
      )}

      {isOwner && (
        <div className="row">
          <input placeholder="collaborator 0x…" value={member} onChange={(e) => setMember(e.target.value.trim())} />
          <input className="narrow" inputMode="numeric" value={units} onChange={(e) => setUnits(e.target.value)} />
          <button
            disabled={!!tx.pending || !isAddress(member) || !/^\d+$/.test(units)}
            onClick={async () => {
              await setMemberUnits(member as Address, BigInt(units));
              setMember("");
              members.refetch();
            }}
          >
            set units
          </button>
        </div>
      )}
      {tx.error && <p className="error">{tx.error}</p>}
    </div>
  );
}

function Subscribers({ app, subgraph, money }: { app: Address; subgraph: string; money: (v: bigint) => string }) {
  const subs = useQuery({ queryKey: ["subscribers", app], queryFn: () => subscribers(subgraph, app) });
  if (!subs.data?.length) return null;
  return (
    <div className="card">
      <h3>Subscribers</h3>
      <table>
        <tbody>
          {subs.data.map((s) => (
            <tr key={s.sender.id}>
              <td>{short(s.sender.id)}</td>
              <td>{money(perMonth(BigInt(s.currentFlowRate)))} / month</td>
              <td className="muted small">since {new Date(Number(s.createdAtTimestamp) * 1000).toLocaleDateString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
