import { createConfig, http } from "wagmi";
import { optimism, optimismSepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";

export const config = createConfig({
  chains: [optimismSepolia, optimism],
  connectors: [injected()],
  transports: {
    // falls back to the public RPCs, which are rate limited
    [optimismSepolia.id]: http(import.meta.env.VITE_RPC_OP_SEPOLIA || undefined),
    [optimism.id]: http(import.meta.env.VITE_RPC_OP || undefined),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof config;
  }
}
