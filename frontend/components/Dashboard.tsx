"use client";

import { useEffect, useState } from "react";
import { BaseError } from "viem";
import { useAccount, useConnect, useDisconnect, usePublicClient, useReadContract, useSwitchChain, useWriteContract } from "wagmi";
import { baseSepolia, lasna } from "@/lib/chain";
import { executorAbi, reactiveAbi, swapSourceAbi } from "@/lib/contracts";
import { deployments } from "@/lib/deployments";
import { loadLoop, type LoopRecord } from "@/lib/loop";

type Phase = "idle" | "waiting" | "complete";

function statusCopy(phase: Phase): string {
  switch (phase) {
    case "idle":
      return "idle";
    case "waiting":
      return "waiting for callback";
    case "complete":
      return "loop complete";
    default: {
      const unreachable: never = phase;
      return unreachable;
    }
  }
}

function statusTip(phase: Phase): string {
  switch (phase) {
    case "idle":
      return "No swap in flight. Connect, then Trigger Swap.";
    case "waiting":
      return "Swap is on Base. Waiting for the Lasna callback.";
    case "complete":
      return "Callback recorded. Latency below is this loop.";
    default: {
      const unreachable: never = phase;
      return unreachable;
    }
  }
}

function Hint({ tip, children }: { tip: string; children: React.ReactNode }) {
  return (
    <div className="hint" tabIndex={0}>
      {children}
      <span className="tip" role="tooltip">
        {tip}
      </span>
    </div>
  );
}

function shortHash(value: string): string {
  if (value.length <= 22) return value;
  return value.slice(0, 10) + "…" + value.slice(-8);
}

function stamp(seconds: number, millis: number | null): string {
  const iso = new Date((millis ?? seconds * 1000)).toISOString();
  return millis == null ? iso : iso;
}

function HashLink({ href, value }: { href: string; value: string }) {
  const [copied, setCopied] = useState(false);

  return (
    <span className="hash">
      <a
        href={href}
        target="_blank"
        rel="noreferrer"
        title="Copy and open"
        onClick={() => {
          void navigator.clipboard.writeText(value);
          setCopied(true);
          window.setTimeout(() => setCopied(false), 1200);
        }}
      >
        {shortHash(value)}
      </a>
      {copied ? <span className="copied">copied</span> : null}
    </span>
  );
}

export function Dashboard() {
  const { address, isConnected, chainId } = useAccount();
  const { connect, connectors, isPending: connecting } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync, isPending: writing } = useWriteContract();
  const baseClient = usePublicClient({ chainId: baseSepolia.id });
  const lasnaClient = usePublicClient({ chainId: lasna.id });

  const [mounted, setMounted] = useState(false);
  const [phase, setPhase] = useState<Phase>("idle");
  const [seeded, setSeeded] = useState(false);
  const [baseline, setBaseline] = useState<bigint | null>(null);
  const [note, setNote] = useState("");
  const [noteBad, setNoteBad] = useState(false);
  const [loop, setLoop] = useState<LoopRecord | null>(null);

  const poll = phase === "waiting" ? 2_000 : 8_000;

  const lower = useReadContract({
    address: deployments.reactive,
    abi: reactiveAbi,
    functionName: "tickLower",
    chainId: lasna.id,
    query: { refetchInterval: poll },
  });
  const upper = useReadContract({
    address: deployments.reactive,
    abi: reactiveAbi,
    functionName: "tickUpper",
    chainId: lasna.id,
    query: { refetchInterval: poll },
  });
  const buffer = useReadContract({
    address: deployments.reactive,
    abi: reactiveAbi,
    functionName: "buffer",
    chainId: lasna.id,
    query: { refetchInterval: poll },
  });
  const count = useReadContract({
    address: deployments.executor,
    abi: executorAbi,
    functionName: "observationCount",
    chainId: baseSepolia.id,
    query: { refetchInterval: poll },
  });
  const latest = useReadContract({
    address: deployments.executor,
    abi: executorAbi,
    functionName: "latest",
    chainId: baseSepolia.id,
    query: { refetchInterval: poll, enabled: (count.data ?? 0n) > 0n },
  });

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    if (seeded || count.data === undefined) return;
    setSeeded(true);
    if (count.data > 0n) setPhase("complete");
  }, [count.data, seeded]);

  useEffect(() => {
    if (baseline == null || count.data === undefined) return;
    if (count.data > baseline) {
      setBaseline(null);
      setPhase("complete");
      setNote("");
      setNoteBad(false);
    }
  }, [baseline, count.data]);

  const observation = latest.data;
  const observed = observation
    ? {
        tick: observation[2],
        originBlockNumber: observation[5],
        originTxHash: observation[6],
        reactiveTimestamp: observation[7],
        callbackTimestamp: observation[8],
      }
    : null;
  const observationKey = observed
    ? `${observed.originBlockNumber.toString()}:${observed.reactiveTimestamp.toString()}`
    : "";

  useEffect(() => {
    if (!observed || !baseClient || !lasnaClient) return;
    const snapshot = observed;
    let cancelled = false;
    loadLoop(baseClient, lasnaClient, {
      originBlockNumber: snapshot.originBlockNumber,
      originTxHash: snapshot.originTxHash,
      tick: Number(snapshot.tick),
      reactiveTimestamp: snapshot.reactiveTimestamp,
      callbackTimestamp: snapshot.callbackTimestamp,
    })
      .then((record) => {
        if (!cancelled) setLoop(record);
      })
      .catch((error: unknown) => {
        if (!cancelled) {
          setNoteBad(true);
          setNote(error instanceof Error ? error.message : "Failed to read the loop.");
        }
      });
    return () => {
      cancelled = true;
    };
    // observationKey is the value identity. `observed` is a fresh object each render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [observationKey, baseClient, lasnaClient]);

  const rangeReady = lower.data !== undefined && upper.data !== undefined;
  const tickText = observed ? String(observed.tick) : "—";

  async function triggerSwap() {
    if (upper.data === undefined) return;
    setNote("");
    setNoteBad(false);
    try {
      if (chainId !== baseSepolia.id) {
        await switchChainAsync({ chainId: baseSepolia.id });
      }
      setBaseline(count.data ?? 0n);
      setPhase("waiting");
      await writeContractAsync({
        address: deployments.swapSource,
        abi: swapSourceAbi,
        functionName: "emitSwap",
        args: [Number(upper.data)],
        chainId: baseSepolia.id,
      });
      setNote("Swap submitted.");
    } catch (error) {
      setBaseline(null);
      setPhase(count.data && count.data > 0n ? "complete" : "idle");
      setNoteBad(true);
      setNote(error instanceof BaseError ? error.shortMessage : "Swap was not sent.");
    }
  }

  const latency =
    loop == null ? "—" : loop.latencyMs != null ? `${loop.latencyMs} ms` : `${loop.callbackSeconds - loop.originSeconds} s`;

  return (
    <div className="shell">
      <header className="topbar">
        <img className="logo" src="/logo.png" alt="Reanchor" />
        <div className="wallet">
          {mounted && isConnected && address ? (
            <>
              <HashLink href={`${deployments.explorers.base}/address/${address}`} value={address} />
              <button type="button" onClick={() => disconnect()}>
                Disconnect
              </button>
            </>
          ) : (
            <Hint tip="Base Sepolia wallet. Required before Trigger Swap.">
              <button
                className="connect"
                type="button"
                disabled={!mounted || connecting || connectors[0] == null}
                onClick={() => {
                  const connector = connectors[0];
                  if (connector) connect({ connector });
                }}
              >
                {mounted && connecting ? "Connecting" : "Connect"}
              </button>
            </Hint>
          )}
        </div>
      </header>

      <section className="stats">
        <Hint tip="Tick bounds the pool must stay inside. A swap outside them starts the loop.">
          <div className="label">// CURRENT RANGE</div>
          <div className="figure range">
            {rangeReady ? (
              <>
                <span>{lower.data}</span>
                <svg className="range-arrow" viewBox="0 0 24 24" aria-hidden="true">
                  <path d="M4 12h14M13 6l6 6-6 6" fill="none" stroke="currentColor" strokeWidth="1.5" />
                </svg>
                <span>{upper.data}</span>
              </>
            ) : (
              "—"
            )}
          </div>
          <div className="sub">{buffer.data === undefined ? "" : `buffer ${buffer.data}`}</div>
        </Hint>
        <Hint tip="Tick of the latest swap. Compared with the range on Lasna.">
          <div className="label">// LAST TICK</div>
          <div className="figure">{loop?.tick ?? tickText}</div>
        </Hint>
        <Hint tip={statusTip(phase)}>
          <div className="label">// STATUS</div>
          <div className={phase === "idle" ? "figure status-value" : "figure status-value accent"}>{statusCopy(phase)}</div>
        </Hint>
      </section>

      <div className="actions">
        <Hint tip="Sends a swap at the upper tick, just outside the range.">
          <button className="trigger" type="button" disabled={!mounted || !isConnected || !rangeReady || writing || phase === "waiting"} onClick={() => void triggerSwap()}>
            Trigger Swap
          </button>
        </Hint>
        <div className={noteBad ? "note bad" : "note"}>{note}</div>
      </div>

      <section className="panel">
        <div className="times">
          <Hint tip="When the swap landed on Base.">
            <div className="label">// ORIGIN</div>
            <div className="time">{loop ? stamp(loop.originSeconds, loop.originMillis) : "—"}</div>
          </Hint>
          <Hint tip="When Lasna requested the callback.">
            <div className="label">// REACTIVE</div>
            <div className="time">{loop ? stamp(loop.reactiveSeconds, null) : "—"}</div>
          </Hint>
          <Hint tip="When the executor recorded the loop on Base.">
            <div className="label">// CALLBACK</div>
            <div className="time">{loop ? stamp(loop.callbackSeconds, loop.callbackMillis) : "—"}</div>
          </Hint>
          <Hint tip="Callback time minus origin time.">
            <div className="label">// END TO END</div>
            <div className="figure accent">{latency}</div>
          </Hint>
        </div>
      </section>

      <section className="panel">
        <div className="label">// TRANSACTIONS</div>
        <div className="rows">
          <div className="row">
            <Hint tip="Swap transaction on Base.">
              <span>origin</span>
            </Hint>
            {loop ? (
              <HashLink href={`${deployments.explorers.base}/tx/${loop.originHash}`} value={loop.originHash} />
            ) : (
              "—"
            )}
          </div>
          <div className="row">
            <Hint tip="Lasna transaction that requested the callback.">
              <span>reactive</span>
            </Hint>
            {loop?.reactiveHash ? (
              <HashLink href={`${deployments.explorers.lasna}/tx/${loop.reactiveHash}`} value={loop.reactiveHash} />
            ) : (
              "—"
            )}
          </div>
          <div className="row">
            <Hint tip="Base transaction that recorded the loop.">
              <span>callback</span>
            </Hint>
            {loop?.callbackHash ? (
              <HashLink href={`${deployments.explorers.base}/tx/${loop.callbackHash}`} value={loop.callbackHash} />
            ) : (
              "—"
            )}
          </div>
        </div>
      </section>

      <section className="contracts">
        <div className="label">// CONTRACTS</div>
        <div className="rows">
          <div className="row">
            <span>pool</span>
            <HashLink href={`${deployments.explorers.base}/address/${deployments.swapSource}`} value={deployments.swapSource} />
          </div>
          <div className="row">
            <span>reactive</span>
            <HashLink href={`${deployments.explorers.lasna}/address/${deployments.reactive}`} value={deployments.reactive} />
          </div>
          <div className="row">
            <span>executor</span>
            <HashLink href={`${deployments.explorers.base}/address/${deployments.executor}`} value={deployments.executor} />
          </div>
        </div>
      </section>
    </div>
  );
}
