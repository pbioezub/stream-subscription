import type { Address } from "viem";
import { optimism, optimismSepolia } from "wagmi/chains";

// addresses from lib/protocol-monorepo/packages/metadata/networks.json
export const CFA_FORWARDER: Address = "0xcfA132E353cB4E398080B9700609bb008eceB125";
export const GDA_FORWARDER: Address = "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08";

type ChainInfo = {
  factory?: Address;
  ethx: Address;
  subgraph: string;
  explorer: string;
};

const env = (v: string | undefined) => (v ? (v as Address) : undefined);

export const CHAINS: Record<number, ChainInfo> = {
  [optimismSepolia.id]: {
    factory: env(import.meta.env.VITE_FACTORY_OP_SEPOLIA) ?? "0xe684dA181b49156d602b814FFfd4C5De6fD52132",
    ethx: "0x0043d7c85C8b96a49A72A92C0B48CdC4720437d7",
    subgraph: "https://subgraph-endpoints.superfluid.dev/optimism-sepolia/protocol-v1",
    explorer: "https://sepolia-optimism.etherscan.io",
  },
  [optimism.id]: {
    factory: env(import.meta.env.VITE_FACTORY_OP),
    ethx: "0x4ac8bD1bDaE47beeF2D1c6Aa62229509b962Aa0d",
    subgraph: "https://subgraph-endpoints.superfluid.dev/optimism-mainnet/protocol-v1",
    explorer: "https://optimistic.etherscan.io",
  },
};
