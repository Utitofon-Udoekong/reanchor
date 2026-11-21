# Reanchor

The full loop completed in **1000 ms**.

Reanchor watches a Uniswap V3-style `Swap` and, when the tick leaves the stored range, a reactive contract on Lasna requests a callback that the Base Sepolia executor records. Omni finalizes in about a second, so the path from the origin log to the destination callback stays inside one second.

## Measured loop

Tick `100` is outside `[-100, 100)`. `ReanchorReactive` made that decision. The executor recorded it.

| Step | Transaction | Time |
| --- | --- | --- |
| Origin Swap, Base block 61576300 | [`0x7cb6b793fcbe4adbcb82454430d2643297b43eacaacec35f76dc2e92fc066b53`](https://sepolia.basescan.org/tx/0x7cb6b793fcbe4adbcb82454430d2643297b43eacaacec35f76dc2e92fc066b53) | 1795237128800 ms |
| Reactive decision, Lasna block 8867227 | [`0x0a25d7194992aa6e73b66c3274c0be06b376d9a57094e41f61f0c40001bc910a`](https://lasna.reactscan.net/tx/0x0a25d7194992aa6e73b66c3274c0be06b376d9a57094e41f61f0c40001bc910a) | 1795237128 s |
| Callback, Base block 61576305 | [`0xfe3e2456bdfbb905fee5fda99e0c09e417be8ca02ef664fcf46bfe5eef14b929`](https://sepolia.basescan.org/tx/0xfe3e2456bdfbb905fee5fda99e0c09e417be8ca02ef664fcf46bfe5eef14b929) | 1795237129800 ms |

End-to-end latency is callback `timestampMs` minus origin `timestampMs`: **1000 ms**.

## Contracts

| Role | Chain | Address |
| --- | --- | --- |
| Swap source | Base Sepolia (84532) | `0x68fA0C5A992A00404b5e3a79D53a24C018A935a5` |
| ReanchorReactive | Lasna (5318007) | `0xcF9fD52A8ECBf7A19be171DAc57e15528A8747Ef` |
| ReanchorExecutor | Base Sepolia (84532) | `0x45f7d7b8cC4F54421eB31FB651121fCFC4f09435` |
| Callback proxy | Base Sepolia | `0x476F44b11F5C942c58f4c8E3d0300E5710743585` |

The reactive contract owns the range decision. It stores the bounds, reads the swap tick, and requests the callback only when the tick is outside. The active range is `-100 <= tick < 100`. The executor authenticates the callback and stores the timestamps.

`ReanchorSwapSource` emits the Uniswap V3 `Swap` event. The reactive contract subscribes to that address.

Deployer and owner: `0xbEB6d51dB6a4A12ebf0b1f870927FfEADd720Aa6`. `pendingOwner` is zero, so `acceptOwnership` was not required.

| Action | Transaction |
| --- | --- |
| Deploy swap source | [`0x519d826fbf086615227457ead4b7951b3733c4e7dfca2090491c2329494c2469`](https://sepolia.basescan.org/tx/0x519d826fbf086615227457ead4b7951b3733c4e7dfca2090491c2329494c2469) |
| Deploy reactive contract with 0.2 lREACT | [`0x6ef983ec2328d0f2cb5d75aaaedd09f88465f6ae3bceb95741d0ccf8107f2828`](https://lasna.reactscan.net/tx/0x6ef983ec2328d0f2cb5d75aaaedd09f88465f6ae3bceb95741d0ccf8107f2828) |
| Deploy executor | [`0x5e151535832d62794a5f5b33b99b42ee9edac8b21f9b33438d1dab8522dd2075`](https://sepolia.basescan.org/tx/0x5e151535832d62794a5f5b33b99b42ee9edac8b21f9b33438d1dab8522dd2075) |
| Fund executor reserves with 0.02 ETH via `depositTo` | [`0xb7706b66ba8215f8b904ef132a34a7569b56ce5d62d84d19c06cf373c73d6653`](https://sepolia.basescan.org/tx/0xb7706b66ba8215f8b904ef132a34a7569b56ce5d62d84d19c06cf373c73d6653) |
| `setExecutor` | [`0xc2432e8c384714cefadb8aef2d0fc1d6fbfe5e1f91d80bdadfe1268267d8a687`](https://lasna.reactscan.net/tx/0xc2432e8c384714cefadb8aef2d0fc1d6fbfe5e1f91d80bdadfe1268267d8a687) |
| `setRange(-100, 100)` | [`0xd1395b06941904ed42637fd4aacb3833af9d07c380dfecacf3b39c4fa19e48bb`](https://lasna.reactscan.net/tx/0xd1395b06941904ed42637fd4aacb3833af9d07c380dfecacf3b39c4fa19e48bb) |

## Faucet

This deployer already held lREACT and Base Sepolia ETH. To fund another key:

- Lasna lREACT: send Base Sepolia ETH to `0x2afaFD298b23b62760711756088F75B7409f5967`, or Ethereum Sepolia ETH to `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`. The rate is 1 ETH to 100 lREACT. Do not send more than 5 ETH in one transaction.
- Base Sepolia gas: use a public Base Sepolia faucet. Keep some ETH on Base after the Lasna faucet transfer. That remaining balance pays for the executor and its callback reserves.

Copy `.env` and set `DEPLOYER_PRIVATE_KEY`, `LASNA_RPC_URL=https://lasna-rpc.rnk.dev/`, and `DESTINATION_RPC_URL=https://sepolia.base.org`.

## Frontend

```powershell
cd frontend
npm install
npm run dev
```

Open `http://localhost:3000`. Connect a wallet with Base Sepolia ETH, then use **Trigger Swap**. The button calls `emitSwap` at the current upper tick, which sits outside the half-open range. After the callback lands, the page shows the three timestamps, the latency, and the transaction links from chain data.

## What is still open

- A provider cannot register a position.
- `onRangeExit` records the trip. It does not move liquidity.

## Tests

```powershell
forge test
```

Solidity 0.8.29. Dependencies are `reactive-lib-omni` (`3ade0dcf`), OpenZeppelin Contracts v5.4.0, and forge-std v1.11.0.
