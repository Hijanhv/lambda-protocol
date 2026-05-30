import hookAbi from "@/abis/LambdaHook.json";
import fundingAbi from "@/abis/Funding.json";
import { addresses } from "./config";

/** Typed handles for the two contracts the dashboard reads/writes. */
export const hook = { address: addresses.hook, abi: hookAbi } as const;
export const funding = { address: addresses.funding, abi: fundingAbi } as const;

/** Minimal ERC-20 ABI for approvals/balances of the pool tokens. */
export const erc20Abi = [
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
  },
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
] as const;
