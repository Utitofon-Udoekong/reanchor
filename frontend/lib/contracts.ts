export const reactiveAbi = [
  {
    type: "function",
    name: "tickLower",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "int24" }],
  },
  {
    type: "function",
    name: "tickUpper",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "int24" }],
  },
  {
    type: "function",
    name: "buffer",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "int24" }],
  },
  {
    type: "event",
    name: "ReanchorRequested",
    inputs: [
      { name: "tick", type: "int24", indexed: true },
      { name: "executor", type: "address", indexed: true },
      { name: "reactiveTimestamp", type: "uint256", indexed: false },
    ],
  },
] as const;

export const executorAbi = [
  {
    type: "function",
    name: "observationCount",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "latest",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "originChainId", type: "uint256" },
      { name: "pool", type: "address" },
      { name: "tick", type: "int24" },
      { name: "tickLower", type: "int24" },
      { name: "tickUpper", type: "int24" },
      { name: "originBlockNumber", type: "uint256" },
      { name: "originTxHash", type: "uint256" },
      { name: "reactiveTimestamp", type: "uint256" },
      { name: "callbackTimestamp", type: "uint256" },
    ],
  },
  {
    type: "event",
    name: "Reanchored",
    inputs: [
      { name: "pool", type: "address", indexed: true },
      { name: "tick", type: "int24", indexed: false },
      { name: "originBlockNumber", type: "uint256", indexed: false },
      { name: "reactiveTimestamp", type: "uint256", indexed: false },
      { name: "callbackTimestamp", type: "uint256", indexed: false },
    ],
  },
] as const;

export const swapSourceAbi = [
  {
    type: "function",
    name: "emitSwap",
    stateMutability: "nonpayable",
    inputs: [{ name: "tick_", type: "int24" }],
    outputs: [],
  },
] as const;
