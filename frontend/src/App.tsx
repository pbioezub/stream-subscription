import { useEffect, useState } from "react";
import { isAddress, type Address } from "viem";
import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { short } from "./lib/format";
import type { config } from "./wagmi";
import { CHAINS } from "./lib/chains";
import { Subscribe } from "./pages/Subscribe";
import { Create } from "./pages/Create";
import { Manage } from "./pages/Manage";

type ChainId = (typeof config)["chains"][number]["id"];

function useHash() {
  const [hash, setHash] = useState(window.location.hash);
  useEffect(() => {
    const onChange = () => setHash(window.location.hash);
    window.addEventListener("hashchange", onChange);
    return () => window.removeEventListener("hashchange", onChange);
  }, []);
  return hash.replace(/^#\/?/, "").split("/");
}

function Wallet() {
  const { address, chainId, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { chains, switchChain } = useSwitchChain();

  if (!isConnected) {
    return (
      <button onClick={() => connect({ connector: connectors[0] })} disabled={isPending}>
        {isPending ? "connecting…" : "connect wallet"}
      </button>
    );
  }
  return (
    <div className="wallet">
      <select value={chainId} onChange={(e) => switchChain({ chainId: Number(e.target.value) as ChainId })}>
        {!CHAINS[chainId!] && <option value={chainId}>unsupported network</option>}
        {chains.map((c) => (
          <option key={c.id} value={c.id}>
            {c.name}
          </option>
        ))}
      </select>
      <button className="link" onClick={() => disconnect()} title="disconnect">
        {short(address!)}
      </button>
    </div>
  );
}

function Home() {
  const [addr, setAddr] = useState("");
  return (
    <section>
      <p>
        Subscriptions paid by streaming money with <a href="https://superfluid.org">Superfluid</a>. You're
        subscribed while your stream is open, and part of the revenue streams on to the creator's collaborators in
        real time.
      </p>
      <form
        className="row"
        onSubmit={(e) => {
          e.preventDefault();
          if (isAddress(addr)) window.location.hash = `#/s/${addr}`;
        }}
      >
        <input placeholder="subscription address 0x…" value={addr} onChange={(e) => setAddr(e.target.value.trim())} />
        <button disabled={!isAddress(addr)}>open</button>
      </form>
      <p>
        Creator? <a href="#/create">Set up a subscription</a>.
      </p>
    </section>
  );
}

export function App() {
  const [page, arg] = useHash();
  const { isConnected, chainId } = useAccount();
  const address = arg && isAddress(arg) ? (arg as Address) : undefined;

  let content = <Home />;
  if (page === "s" && address) content = <Subscribe app={address} />;
  else if (page === "manage" && address) content = <Manage app={address} />;
  else if (page === "create") content = <Create />;

  return (
    <main>
      <header>
        <a href="#/" className="logo">
          stream subscription
        </a>
        <nav>
          <a href="#/create">create</a>
          <Wallet />
        </nav>
      </header>
      {isConnected && !CHAINS[chainId!] && <p className="error">Switch to Optimism or OP Sepolia.</p>}
      {content}
    </main>
  );
}
