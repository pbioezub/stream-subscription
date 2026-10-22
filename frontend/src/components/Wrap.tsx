import { useState } from "react";
import { zeroAddress, parseEther, type Address } from "viem";
import { useAccount, useBalance, useChainId, useReadContracts } from "wagmi";
import { erc20Abi, superTokenAbi } from "../abi/superfluid";
import { CHAINS } from "../lib/chains";
import { fmt } from "../lib/format";
import { useTx } from "../lib/useTx";

/// Get Super Tokens: wrap native ETH into ETHx, or approve + upgrade the underlying ERC20.
export function Wrap({ token, symbol }: { token: Address; symbol: string }) {
  const chainId = useChainId();
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const tx = useTx();
  const eth = useBalance({ address });

  const underlying = useReadContracts({
    allowFailure: false,
    contracts: [{ address: token, abi: superTokenAbi, functionName: "getUnderlyingToken" }],
  });
  const underlyingAddr = underlying.data?.[0];
  const isNative = token.toLowerCase() === CHAINS[chainId]?.ethx.toLowerCase();
  const erc20 = useReadContracts({
    allowFailure: false,
    query: { enabled: !!underlyingAddr && underlyingAddr !== zeroAddress },
    contracts: [
      { address: underlyingAddr!, abi: erc20Abi, functionName: "symbol" },
      { address: underlyingAddr!, abi: erc20Abi, functionName: "decimals" },
      { address: underlyingAddr!, abi: erc20Abi, functionName: "balanceOf", args: [address!] },
    ],
  });

  if (!isNative && !erc20.data) return null;

  async function wrap() {
    if (isNative) {
      await tx.send("wrapping", {
        address: token,
        abi: superTokenAbi,
        functionName: "upgradeByETH",
        value: parseEther(amount),
      });
    } else {
      const [, decimals] = erc20.data!;
      const superAmount = parseEther(amount); // super tokens always have 18 decimals
      const approveAmount = superAmount / 10n ** BigInt(18 - decimals);
      const ok = await tx.send("approving", {
        address: underlyingAddr!,
        abi: erc20Abi,
        functionName: "approve",
        args: [token, approveAmount],
      });
      if (ok) await tx.send("wrapping", { address: token, abi: superTokenAbi, functionName: "upgrade", args: [superAmount] });
    }
    setAmount("");
  }

  const from = isNative ? "ETH" : erc20.data![0];
  const have = isNative ? eth.data?.value ?? 0n : erc20.data![2];
  const haveDecimals = isNative ? 18 : erc20.data![1];

  return (
    <details className="card">
      <summary>
        Need {symbol}? Wrap {from}
      </summary>
      <p className="muted small">
        You have {fmt(have, haveDecimals)} {from}
      </p>
      <div className="row">
        <input placeholder="amount" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
        <button onClick={wrap} disabled={!!tx.pending || !Number(amount)}>
          {tx.pending ?? "wrap"}
        </button>
      </div>
      {tx.error && <p className="error">{tx.error}</p>}
    </details>
  );
}
