"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";
import { createConfig, http, WagmiProvider } from "wagmi";
import { injected } from "wagmi/connectors";
import { baseSepolia, lasna } from "@/lib/chain";
import { deployments } from "@/lib/deployments";

const config = createConfig({
  chains: [baseSepolia, lasna],
  connectors: [injected()],
  transports: {
    [baseSepolia.id]: http(deployments.destinationRpc),
    [lasna.id]: http(deployments.lasnaRpc),
  },
});

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  );
}
