import { useQuery } from "@tanstack/react-query";
import {
  formatUnits,
  parseAbiItem,
  type Address,
  type PublicClient,
} from "viem";
import { useChainId, usePublicClient } from "wagmi";
import { getDeployment } from "../config";

const DEPLOY_START_BLOCK = 269425864n;

const swapEvent = parseAbiItem(
  "event Swap(address indexed sender,uint256 amountIn,uint256 amountOut,bool aToB,address indexed recipient)",
);
const liquidatedEvent = parseAbiItem(
  "event Liquidated(address indexed user,address indexed liquidator,uint256 repayAmount,uint256 collateralSeized)",
);
const vaultDepositEvent = parseAbiItem(
  "event Deposit(address indexed sender,address indexed owner,uint256 assets,uint256 shares)",
);
const yieldHarvestedEvent = parseAbiItem(
  "event YieldHarvested(uint256 profit,uint256 fee,address indexed caller)",
);

export interface RpcSwap {
  id: string;
  sender: string;
  recipient: string;
  direction: string;
  amountIn: string;
  amountOut: string;
  timestamp: number;
  txHash: string;
}

export interface RpcDayData {
  id: string;
  date: number;
  dailyVolumeTKA: string;
  dailyVolumeTKB: string;
  dailySwaps: number;
  dailyLiquidations: number;
  dailyVaultDeposits: string;
  dailyYieldHarvested: string;
}

function analyticsStartBlock() {
  const configured = Number(
    import.meta.env.VITE_ARB_ANALYTICS_START_BLOCK || 0,
  );
  return configured > 0 ? BigInt(configured) : DEPLOY_START_BLOCK;
}

async function getBlockTimestamp(
  publicClient: PublicClient,
  cache: Map<bigint, number>,
  blockNumber: bigint,
) {
  const cached = cache.get(blockNumber);
  if (cached) return cached;
  const block = await publicClient.getBlock({ blockNumber });
  const timestamp = Number(block.timestamp);
  cache.set(blockNumber, timestamp);
  return timestamp;
}

function getDay(days: Map<number, RpcDayData>, timestamp: number) {
  const day = Math.floor(timestamp / 86400);
  const existing = days.get(day);
  if (existing) return existing;

  const created: RpcDayData = {
    id: String(day),
    date: day,
    dailyVolumeTKA: "0",
    dailyVolumeTKB: "0",
    dailySwaps: 0,
    dailyLiquidations: 0,
    dailyVaultDeposits: "0",
    dailyYieldHarvested: "0",
  };
  days.set(day, created);
  return created;
}

function addDecimal(a: string, b: string) {
  return String(Number(a) + Number(b));
}

export function useRpcAnalytics() {
  const chainId = useChainId();
  const publicClient = usePublicClient();
  const d = getDeployment(chainId);

  return useQuery({
    queryKey: ["rpcAnalytics", chainId, d?.amm, d?.lending, d?.vault],
    enabled: !!publicClient && !!d?.amm && !!d?.lending && !!d?.vault,
    refetchInterval: 30_000,
    queryFn: async () => {
      if (!publicClient || !d) {
        return { swaps: [] as RpcSwap[], protocolDayDatas: [] as RpcDayData[] };
      }

      const fromBlock = analyticsStartBlock();
      const timestampCache = new Map<bigint, number>();
      const days = new Map<number, RpcDayData>();

      const [swapLogs, liquidationLogs, vaultDepositLogs, yieldLogs] =
        await Promise.all([
          publicClient.getLogs({
            address: d.amm as Address,
            event: swapEvent,
            fromBlock,
            toBlock: "latest",
          }),
          publicClient.getLogs({
            address: d.lending as Address,
            event: liquidatedEvent,
            fromBlock,
            toBlock: "latest",
          }),
          publicClient.getLogs({
            address: d.vault as Address,
            event: vaultDepositEvent,
            fromBlock,
            toBlock: "latest",
          }),
          publicClient.getLogs({
            address: d.vault as Address,
            event: yieldHarvestedEvent,
            fromBlock,
            toBlock: "latest",
          }),
        ]);

      const swaps = await Promise.all(
        swapLogs.map(async (log) => {
          const timestamp = await getBlockTimestamp(
            publicClient,
            timestampCache,
            log.blockNumber,
          );
          const amountIn = formatUnits(log.args.amountIn ?? 0n, 18);
          const amountOut = formatUnits(log.args.amountOut ?? 0n, 18);
          const day = getDay(days, timestamp);
          const isContractAToB = Boolean(log.args.aToB);

          day.dailySwaps += 1;
          if (isContractAToB) {
            day.dailyVolumeTKB = addDecimal(day.dailyVolumeTKB, amountIn);
            day.dailyVolumeTKA = addDecimal(day.dailyVolumeTKA, amountOut);
          } else {
            day.dailyVolumeTKA = addDecimal(day.dailyVolumeTKA, amountIn);
            day.dailyVolumeTKB = addDecimal(day.dailyVolumeTKB, amountOut);
          }

          return {
            id: `${log.transactionHash}-${log.logIndex}`,
            sender: log.args.sender ?? "",
            recipient: log.args.recipient ?? "",
            direction: isContractAToB ? "TKB -> TKA" : "TKA -> TKB",
            amountIn,
            amountOut,
            timestamp,
            txHash: log.transactionHash,
          };
        }),
      );

      await Promise.all(
        liquidationLogs.map(async (log) => {
          const timestamp = await getBlockTimestamp(
            publicClient,
            timestampCache,
            log.blockNumber,
          );
          getDay(days, timestamp).dailyLiquidations += 1;
        }),
      );

      await Promise.all(
        vaultDepositLogs.map(async (log) => {
          const timestamp = await getBlockTimestamp(
            publicClient,
            timestampCache,
            log.blockNumber,
          );
          const day = getDay(days, timestamp);
          day.dailyVaultDeposits = addDecimal(
            day.dailyVaultDeposits,
            formatUnits(log.args.assets ?? 0n, 18),
          );
        }),
      );

      await Promise.all(
        yieldLogs.map(async (log) => {
          const timestamp = await getBlockTimestamp(
            publicClient,
            timestampCache,
            log.blockNumber,
          );
          const day = getDay(days, timestamp);
          day.dailyYieldHarvested = addDecimal(
            day.dailyYieldHarvested,
            formatUnits(log.args.profit ?? 0n, 18),
          );
        }),
      );

      return {
        swaps: swaps.sort((a, b) => b.timestamp - a.timestamp),
        protocolDayDatas: Array.from(days.values()).sort(
          (a, b) => b.date - a.date,
        ),
      };
    },
  });
}
