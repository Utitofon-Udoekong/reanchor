import { defineChain } from "viem";
import { baseSepolia } from "viem/chains";
import { deployments } from "./deployments";

export { baseSepolia };

export const lasna = defineChain({
  id: deployments.reactiveChainId,
  name: "Reactive Lasna",
  nativeCurrency: { name: "lREACT", symbol: "lREACT", decimals: 18 },
  rpcUrls: { default: { http: [deployments.lasnaRpc] } },
  blockExplorers: {
    default: { name: "Reactscan", url: deployments.explorers.lasna },
  },
});
