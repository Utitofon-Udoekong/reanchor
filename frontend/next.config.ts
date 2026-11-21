import type { NextConfig } from "next";
import { createRequire } from "node:module";
import path from "node:path";

const require = createRequire(import.meta.url);
const wagmiDir = path.dirname(require.resolve("wagmi/package.json"));
// The connectors barrel pulls Coinbase, MetaMask, and WalletConnect. The page
// only needs window.ethereum, so resolve that one module directly.
const injectedEntry = path.join(
  wagmiDir,
  "..",
  "@wagmi",
  "core",
  "dist",
  "esm",
  "connectors",
  "injected.js",
);

const nextConfig: NextConfig = {
  reactStrictMode: true,
  webpack: (config) => {
    const alias = config.resolve?.alias;
    if (alias && !Array.isArray(alias)) {
      alias["wagmi/connectors"] = injectedEntry;
    }
    return config;
  },
};

export default nextConfig;
