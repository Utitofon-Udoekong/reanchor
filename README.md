# Reanchor

The full loop completed in **1000 ms**.

## The problem

A Uniswap v3 position earns fees only while the price stays between two ticks. Those ticks are the position's range. When a swap pushes the price outside, the position stops earning until someone moves it back around the price. That someone is usually an off-chain bot watching the chain, racing the mempool, and waiting on the destination chain.

Reanchor makes the chain do the watching. A swap outside the stored range is noticed on Lasna. About a second later a callback lands on Base Sepolia. The provider does not run a keeper. The delay is a receipt: three timestamps and three transactions. That same callback is where the position is moved back around the new tick, while the price is still nearby.

## How it works

The loop is one round trip, three transactions, once. It starts on Base, goes through Lasna, and is recorded back on Base. Lasna is the middle. The stored record stays on Base.

1. **Origin.** A swap on Base Sepolia emits the Uniswap v3 `Swap` event. The tick in that log is where the swap put the price.
2. **Reactive.** `ReanchorReactive` on Lasna is subscribed to that log. It owns the range decision. `react` reads the tick and compares it with the stored range. Inside the range, it returns and does nothing. Outside, it calls `SYSTEM.requestCallbackV_1_0`. The first payload argument is `address(0)`, which the network overwrites with the reactive contract's address.
3. **Callback.** `ReanchorExecutor` on Base Sepolia accepts the call only from the callback proxy and only from that reactive contract. It writes down the tick, the origin block, the Lasna time, and the Base time.

**End to end** is the Base callback time minus the Base swap time. The 1000 ms includes the hop through Lasna.

The stored range is **-100 to 100**. A tick counts as inside while it is at least -100 and still below 100. Tick 100 is the first tick outside, which is why the last tick on the page is 100 and the loop has already run. The page draws this as **-100 → 100** so the separator is not read as a second minus.

The measured trip used `ReanchorSwapSource`. That contract emits a real Uniswap v3 `Swap` log and stands in for a pool. There was no position NFT and no liquidity behind -100 to 100. **Trigger Swap** emits that log at the current upper tick, which is outside the range, so Lasna requests another callback. The button does nothing until a wallet is connected, and it does nothing while the status is "waiting for callback".

If a provider has registered a position, the executor does more after it records the trip. The provider must own the NFT and have called `setApprovalForAll` for the executor. The executor then exits the position and mints a new one of the same width, centered on the delivered tick: `decreaseLiquidity` of the full liquidity, `collect`, `burn`, and `mint`. The new ticks are multiples of the pool's `tickSpacing`. Mint slippage defaults to 50 basis points (0.50 percent). The contract owner sets the position manager and the slippage. The provider registers their own NFT.

That reposition path is implemented and tested. It was not part of the measured loop. The deployed executor has no position manager, and no position was registered.

| Step | Transaction | Time |
| --- | --- | --- |
| Origin Swap, Base block 61576300 | [`0x7cb6b793fcbe4adbcb82454430d2643297b43eacaacec35f76dc2e92fc066b53`](https://sepolia.basescan.org/tx/0x7cb6b793fcbe4adbcb82454430d2643297b43eacaacec35f76dc2e92fc066b53) | 1795237128800 ms |
| Reactive decision, Lasna block 8867227 | [`0x0a25d7194992aa6e73b66c3274c0be06b376d9a57094e41f61f0c40001bc910a`](https://lasna.reactscan.net/tx/0x0a25d7194992aa6e73b66c3274c0be06b376d9a57094e41f61f0c40001bc910a) | 1795237128 s |
| Callback, Base block 61576305 | [`0xfe3e2456bdfbb905fee5fda99e0c09e417be8ca02ef664fcf46bfe5eef14b929`](https://sepolia.basescan.org/tx/0xfe3e2456bdfbb905fee5fda99e0c09e417be8ca02ef664fcf46bfe5eef14b929) | 1795237129800 ms |

| Role | Chain | Address |
| --- | --- | --- |
| Swap source | Base Sepolia (84532) | `0x68fA0C5A992A00404b5e3a79D53a24C018A935a5` |
| ReanchorReactive | Lasna (5318007) | `0xcF9fD52A8ECBf7A19be171DAc57e15528A8747Ef` |
| ReanchorExecutor | Base Sepolia (84532) | `0x45f7d7b8cC4F54421eB31FB651121fCFC4f09435` |
| Callback proxy | Base Sepolia | `0x476F44b11F5C942c58f4c8E3d0300E5710743585` |

Deployer and owner: `0xbEB6d51dB6a4A12ebf0b1f870927FfEADd720Aa6`.

## Key features

Open `http://localhost:3000` after the frontend commands below. Connect a wallet that holds Base Sepolia ETH. That is the only setup the page needs.

The page is the receipt of the last loop:

- **Current range** is the tick bounds the pool must stay inside. The deployed bounds are -100 to 100.
- **Last tick** is the tick of the latest swap. Lasna compared it with the range. 100 is outside.
- **Status** is `idle` when nothing is in flight, `waiting for callback` after the swap is on Base and Lasna has not called back yet, and `loop complete` when the callback has been recorded.
- **Origin** is when the swap landed on Base. **Reactive** is when Lasna requested the callback. **Callback** is when the executor recorded the loop on Base.
- **End to end** is the callback time minus the origin time. The number on the page is 1000 ms.
- The three transaction rows are the swap, the Lasna request, and the recorded callback. A hash copies on click and opens the explorer.

**Trigger Swap** sends `emitSwap` at the current upper tick. That tick sits outside the half-open range, so the reactive contract requests a new callback. The same fields update from chain data when the callback lands.

A provider who owns a Uniswap v3 position NFT can call `registerPosition` after approving the executor with `setApprovalForAll`. The next out-of-range callback records the trip and then moves that position.

## Tech stack

- Solidity 0.8.29, Foundry, `reactive-lib-omni` (`3ade0dcf`), OpenZeppelin Contracts v5.4.0, forge-std v1.11.0
- Lasna (5318007), `https://lasna-rpc.rnk.dev/`. Base Sepolia (84532), `https://sepolia.base.org`
- Next.js App Router, React, wagmi, viem
- Uniswap v3 `INonfungiblePositionManager` and pool `tickSpacing`

## Hackathon requirements

**Execution.** The three transactions above are on-chain: the origin swap, the Lasna reactive transaction, and the Base callback. Latency is callback `timestampMs` minus origin `timestampMs`: **1000 ms**.

**Integration.** The range check and the callback request live in `ReanchorReactive.react`. The executor does not decide whether the tick is outside the range. It authenticates the callback, records the timestamps, and, when a position is registered, repositions it. Omni finalizes in about a second, so this path from the origin log to the destination callback stays inside one second.

**Usefulness.** The product is the proof that the tick left the range, plus a callback the provider can use to push the position back in. The measured deployment is the proof: tick 100 left [-100, 100), and the callback arrived in 1000 ms. The push-back is `registerPosition` and the exit-then-mint in `onRangeExit`. It is covered by tests. It is not in the three transactions above.

**Craft.** `forge test` covers unauthorized callers, the wrong reactive sender, an in-range no-op, an out-of-range callback request, and the position-manager call sequence.

```powershell
forge test
```

```powershell
cd frontend
npm install
npm run dev
```

Open `http://localhost:3000`. Connect a wallet with Base Sepolia ETH, then use **Trigger Swap**.

To fund another key:

- Lasna lREACT: send Base Sepolia ETH to `0x2afaFD298b23b62760711756088F75B7409f5967`, or Ethereum Sepolia ETH to `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`. The rate is 1 ETH to 100 lREACT. Do not send more than 5 ETH in one transaction. Keep some Base ETH for destination gas.
- Base Sepolia gas: use a public Base Sepolia faucet. The executor's callback reserve was funded with 0.02 ETH through the proxy `depositTo`.

Copy `.env` and set `DEPLOYER_PRIVATE_KEY`, `LASNA_RPC_URL=https://lasna-rpc.rnk.dev/`, and `DESTINATION_RPC_URL=https://sepolia.base.org`.

`ReanchorReactive` still requests the callback with a 500_000 gas limit. That limit was left unchanged.
