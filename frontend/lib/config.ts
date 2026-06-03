import { http, createConfig } from "wagmi";
import { injected } from "wagmi/connectors";
import { defineChain } from "viem";

/** The chain the hook is deployed on. Defaults to Unichain Sepolia; override via env. */
const chainId = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? 1301);
const rpcUrl = process.env.NEXT_PUBLIC_RPC_URL ?? "https://sepolia.unichain.org";

export const hookChain = defineChain({
  id: chainId,
  name: process.env.NEXT_PUBLIC_CHAIN_NAME ?? "Unichain Sepolia",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [rpcUrl] } },
});

export const wagmiConfig = createConfig({
  chains: [hookChain],
  connectors: [injected()],
  transports: { [hookChain.id]: http(rpcUrl) },
});

const required = (v: string | undefined, name: string): `0x${string}` => {
  if (!v) {
    // Surfaced clearly in the UI rather than throwing at import time.
    return "0x0000000000000000000000000000000000000000";
  }
  return v as `0x${string}`;
};

export const addresses = {
  hook: required(process.env.NEXT_PUBLIC_HOOK_ADDRESS, "HOOK_ADDRESS"),
  funding: required(process.env.NEXT_PUBLIC_FUNDING_ADDRESS, "FUNDING_ADDRESS"),
  poolId: required(process.env.NEXT_PUBLIC_POOL_ID, "POOL_ID"),
  token0: required(process.env.NEXT_PUBLIC_TOKEN0, "TOKEN0"),
  token1: required(process.env.NEXT_PUBLIC_TOKEN1, "TOKEN1"),
};

/** Block explorer base for the hook's chain (tx/address links). Override via env. */
export const explorerUrl =
  process.env.NEXT_PUBLIC_EXPLORER_URL ?? "https://sepolia.uniscan.xyz";

export const tokenMeta = {
  token0: {
    symbol: process.env.NEXT_PUBLIC_TOKEN0_SYMBOL ?? "WETH",
    decimals: Number(process.env.NEXT_PUBLIC_TOKEN0_DECIMALS ?? 18),
  },
  token1: {
    symbol: process.env.NEXT_PUBLIC_TOKEN1_SYMBOL ?? "USDC",
    decimals: Number(process.env.NEXT_PUBLIC_TOKEN1_DECIMALS ?? 6),
  },
};

/**
 * Uniswap sorts a pool's currencies by address (currency0 = the lower one). The hook reports
 * `currentDelta` in currency0 units and {Funding} pays in currency1, so we sort the *display*
 * metadata to match the on-chain order. This way the dashboard labels and scales every value
 * correctly no matter which way round the env TOKEN0/TOKEN1 happen to be set.
 */
const token0IsLower = addresses.token0.toLowerCase() < addresses.token1.toLowerCase();
export const currency0 = token0IsLower
  ? { address: addresses.token0, ...tokenMeta.token0 }
  : { address: addresses.token1, ...tokenMeta.token1 };
export const currency1 = token0IsLower
  ? { address: addresses.token1, ...tokenMeta.token1 }
  : { address: addresses.token0, ...tokenMeta.token0 };

export const isConfigured =
  addresses.hook !== "0x0000000000000000000000000000000000000000" &&
  addresses.funding !== "0x0000000000000000000000000000000000000000";
