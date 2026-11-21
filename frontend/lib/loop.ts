import { numberToHex, toHex, type PublicClient } from "viem";
import { executorAbi, reactiveAbi } from "./contracts";
import { deployments } from "./deployments";

export type Observation = {
  originBlockNumber: bigint;
  originTxHash: bigint;
  tick: number;
  reactiveTimestamp: bigint;
  callbackTimestamp: bigint;
};

export type LoopRecord = {
  tick: number;
  originSeconds: number;
  originMillis: number | null;
  reactiveSeconds: number;
  callbackSeconds: number;
  callbackMillis: number | null;
  latencyMs: number | null;
  originHash: `0x${string}`;
  reactiveHash: `0x${string}` | null;
  callbackHash: `0x${string}` | null;
};

type RpcBlock = {
  timestamp: `0x${string}`;
  timestampMs?: `0x${string}`;
};

const CHUNK = 200n;

async function blockStamp(client: PublicClient, blockNumber: bigint) {
  const raw = (await client.request({
    method: "eth_getBlockByNumber",
    params: [numberToHex(blockNumber), false],
  })) as RpcBlock;
  const seconds = Number(BigInt(raw.timestamp));
  const millis = raw.timestampMs == null ? null : Number(BigInt(raw.timestampMs));
  return { seconds, millis };
}

async function scanLogs<T extends { args: Record<string, unknown>; transactionHash: `0x${string}` | null }>(
  readWindow: (fromBlock: bigint, toBlock: bigint) => Promise<readonly T[]>,
  start: bigint,
  end: bigint,
  match: (log: T) => boolean,
): Promise<T | null> {
  let found: T | null = null;
  const last = end < start ? start : end;
  for (let cursor = start; cursor <= last; cursor += CHUNK) {
    const toBlock = cursor + CHUNK - 1n > last ? last : cursor + CHUNK - 1n;
    const logs = await readWindow(cursor, toBlock);
    for (const log of logs) {
      if (match(log)) found = log;
    }
  }
  return found;
}

export async function loadLoop(
  base: PublicClient,
  lasnaClient: PublicClient,
  observation: Observation,
): Promise<LoopRecord> {
  const origin = await blockStamp(base, observation.originBlockNumber);
  const callbackEnd = observation.originBlockNumber + 40n;
  const baseHead = await base.getBlockNumber();
  const callbackLog = await scanLogs(
    (fromBlock, toBlock) =>
      base.getLogs({
        address: deployments.executor,
        event: executorAbi[2],
        fromBlock,
        toBlock,
      }),
    observation.originBlockNumber,
    callbackEnd < baseHead ? callbackEnd : baseHead,
    (log) => log.args.originBlockNumber === observation.originBlockNumber,
  );

  const callbackStamp = callbackLog
    ? await blockStamp(base, callbackLog.blockNumber)
    : { seconds: Number(observation.callbackTimestamp), millis: null };

  const lasnaHead = await lasnaClient.getBlockNumber();
  const recentStart = lasnaHead > 4_000n ? lasnaHead - 4_000n : 0n;
  const deployedEnd = deployments.reactiveFromBlock + 5_000n;
  const reactiveLog =
    (await scanLogs(
      (fromBlock, toBlock) =>
        lasnaClient.getLogs({
          address: deployments.reactive,
          event: reactiveAbi[3],
          fromBlock,
          toBlock,
        }),
      deployments.reactiveFromBlock,
      deployedEnd < lasnaHead ? deployedEnd : lasnaHead,
      (log) => log.args.reactiveTimestamp === observation.reactiveTimestamp,
    )) ??
    (await scanLogs(
      (fromBlock, toBlock) =>
        lasnaClient.getLogs({
          address: deployments.reactive,
          event: reactiveAbi[3],
          fromBlock,
          toBlock,
        }),
      recentStart,
      lasnaHead,
      (log) => log.args.reactiveTimestamp === observation.reactiveTimestamp,
    ));

  const latencyMs =
    origin.millis != null && callbackStamp.millis != null ? callbackStamp.millis - origin.millis : null;

  return {
    tick: observation.tick,
    originSeconds: origin.seconds,
    originMillis: origin.millis,
    reactiveSeconds: Number(observation.reactiveTimestamp),
    callbackSeconds: callbackStamp.seconds,
    callbackMillis: callbackStamp.millis,
    latencyMs,
    originHash: toHex(observation.originTxHash, { size: 32 }),
    reactiveHash: reactiveLog?.transactionHash ?? null,
    callbackHash: callbackLog?.transactionHash ?? null,
  };
}
