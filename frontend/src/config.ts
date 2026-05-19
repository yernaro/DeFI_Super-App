import { createConfig, http } from "wagmi";
import { arbitrumSepolia, optimismSepolia, baseSepolia } from "wagmi/chains";
import { injected, walletConnect } from "wagmi/connectors";

const projectId =
  import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || "demo-project-id";

export const SUPPORTED_CHAINS = [
  arbitrumSepolia,
  optimismSepolia,
  baseSepolia,
] as const;

export const config = createConfig({
  chains: SUPPORTED_CHAINS,
  connectors: [
    injected(), // MetaMask + any injected wallet
    walletConnect({ projectId }), // WalletConnect v2
  ],
  transports: {
    [arbitrumSepolia.id]: http(import.meta.env.VITE_ARBITRUM_SEPOLIA_RPC || ""),
    [optimismSepolia.id]: http(import.meta.env.VITE_OPTIMISM_SEPOLIA_RPC || ""),
    [baseSepolia.id]: http(import.meta.env.VITE_BASE_SEPOLIA_RPC || ""),
  },
});

export const DEPLOYMENT = {
  [arbitrumSepolia.id]: {
    govToken:
      import.meta.env.VITE_ARB_GOV_TOKEN ||
      "0x0000000000000000000000000000000000000001",
    amm:
      import.meta.env.VITE_ARB_AMM ||
      "0x0000000000000000000000000000000000000002",
    lending:
      import.meta.env.VITE_ARB_LENDING ||
      "0x0000000000000000000000000000000000000003",
    vault:
      import.meta.env.VITE_ARB_VAULT ||
      "0x0000000000000000000000000000000000000004",
    governor:
      import.meta.env.VITE_ARB_GOVERNOR ||
      "0x0000000000000000000000000000000000000005",
    timelock:
      import.meta.env.VITE_ARB_TIMELOCK ||
      "0x0000000000000000000000000000000000000006",
    treasury:
      import.meta.env.VITE_ARB_TREASURY ||
      "0x0000000000000000000000000000000000000007",
    tokenA:
      import.meta.env.VITE_ARB_TOKEN_A ||
      "0x0000000000000000000000000000000000000008",
    tokenB:
      import.meta.env.VITE_ARB_TOKEN_B ||
      "0x0000000000000000000000000000000000000009",
    subgraph:
      import.meta.env.VITE_ARB_SUBGRAPH_URL ||
      "https://api.studio.thegraph.com/query/xxxxx/defi-super-app/version/latest",
  },
} as const;

export function getDeployment(chainId: number) {
  return DEPLOYMENT[chainId as keyof typeof DEPLOYMENT] || null;
}
