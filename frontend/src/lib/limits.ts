import { zeroAddress, type Address } from "viem";
import { useReadContracts } from "wagmi";
import { streamSubscriptionAbi } from "../abi/StreamSubscription";

/// Views added after v0.1.0. Older deployments don't have them, so every field is optional.
export function useNewViews(app: Address, user: Address | undefined) {
  const base = { address: app, abi: streamSubscriptionAbi } as const;
  const who = user ?? zeroAddress;
  const r = useReadContracts({
    allowFailure: true,
    query: { refetchInterval: 10_000 },
    contracts: [
      { ...base, functionName: "maxSubscribers" },
      { ...base, functionName: "seatsLeft" },
      { ...base, functionName: "subscribedSince", args: [who] },
      { ...base, functionName: "totalStreamed", args: [who] },
    ],
  });
  const get = (i: number) => (r.data?.[i]?.status === "success" ? (r.data[i].result as bigint) : undefined);
  const max = get(0);
  return {
    loading: r.isLoading,
    max: max === 0n ? undefined : max, // 0 = no limit
    limitSupported: max !== undefined,
    seatsLeft: max ? get(1) : undefined,
    since: get(2) || undefined,
    totalStreamed: get(3),
  };
}
