# Demo video

About two minutes. Record the page at `http://localhost:3000` and the three explorer links in the README.

1. **The problem, 20 seconds.** "A Uniswap v3 position only earns fees inside a tick range. Reanchor notices when a swap leaves that range and asks Base to record the trip. The measured trip took 1000 milliseconds."
2. **The page, 30 seconds.** Show **-100 → 100**, last tick **100**, and status **loop complete**. Hover **Current range**, then **End to end**. Point at **1000 ms** and the three transaction links.
3. **The chain, 40 seconds.** Open the origin swap on BaseScan, the reactive transaction on Reactscan, and the callback on BaseScan. Say: "Lasna made the range decision. Base only recorded the callback."
4. **What the callback can do, 20 seconds.** "If a provider has registered a position and approved the executor, this same callback exits the position and mints a new range around the tick. That path is tested. This measured loop did not move liquidity, because no position was registered."
5. **Close, 10 seconds.** "The reactive contract owns the decision. The loop you just saw completed in 1000 milliseconds."
