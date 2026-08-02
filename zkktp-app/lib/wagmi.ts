import { http, createConfig } from "wagmi";
import { defineChain } from "viem";
import { injected } from "wagmi/connectors";

export const liskSepolia = defineChain({
  id: 4202,
  name: "Lisk Sepolia",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: {
      http: [process.env.NEXT_PUBLIC_RPC_URL ?? "https://rpc.sepolia-api.lisk.com"],
    },
  },
  blockExplorers: {
    default: { name: "Blockscout", url: "https://sepolia-blockscout.lisk.com" },
  },
  testnet: true,
});

export const config = createConfig({
  chains: [liskSepolia],
  connectors: [injected()],
  transports: {
    [liskSepolia.id]: http(),
  },
  ssr: true,
});
