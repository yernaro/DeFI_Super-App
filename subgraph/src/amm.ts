import { BigDecimal, BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  LiquidityAdded,
  LiquidityRemoved,
  Swap as SwapEvent,
  Sync,
} from "../generated/AMM/AMM";
import {
  Pool,
  Swap,
  LiquidityEvent,
  ProtocolDayData,
} from "../generated/schema";

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────
const EIGHTEEN = BigDecimal.fromString("1000000000000000000");

function toDecimal(raw: BigInt): BigDecimal {
  return raw.toBigDecimal().div(EIGHTEEN);
}

function loadOrCreatePool(address: Bytes): Pool {
  let id = address.toHexString();
  let pool = Pool.load(id);
  if (!pool) {
    pool = new Pool(id);
    pool.tokenA = Bytes.empty();
    pool.tokenB = Bytes.empty();
    pool.reserveA = BigDecimal.zero();
    pool.reserveB = BigDecimal.zero();
    pool.totalLPSupply = BigDecimal.zero();
    pool.totalVolumeA = BigDecimal.zero();
    pool.totalVolumeB = BigDecimal.zero();
    pool.txCount = BigInt.zero();
    pool.createdAt = BigInt.zero();
    pool.updatedAt = BigInt.zero();
  }
  return pool;
}

function loadOrCreateDayData(timestamp: BigInt): ProtocolDayData {
  let dayId = timestamp.toI32() / 86400;
  let id = dayId.toString();
  let data = ProtocolDayData.load(id);
  if (!data) {
    data = new ProtocolDayData(id);
    data.date = dayId;
    data.dailyVolumeA = BigDecimal.zero();
    data.dailyVolumeB = BigDecimal.zero();
    data.dailySwaps = BigInt.zero();
    data.dailyLiquidations = BigInt.zero();
    data.dailyVaultDeposits = BigDecimal.zero();
    data.dailyYieldHarvested = BigDecimal.zero();
  }
  return data;
}

// ─────────────────────────────────────────────────────────────────────────────
// Event handlers
// ─────────────────────────────────────────────────────────────────────────────

export function handleSync(event: Sync): void {
  let pool = loadOrCreatePool(event.address);
  pool.reserveA = toDecimal(event.params.reserveA);
  pool.reserveB = toDecimal(event.params.reserveB);
  pool.updatedAt = event.block.timestamp;
  pool.save();
}

export function handleSwap(event: SwapEvent): void {
  let pool = loadOrCreatePool(event.address);
  pool.txCount = pool.txCount.plus(BigInt.fromI32(1));

  let amtIn  = toDecimal(event.params.amountIn);
  let amtOut = toDecimal(event.params.amountOut);

  if (event.params.aToB) {
    pool.totalVolumeA = pool.totalVolumeA.plus(amtIn);
  } else {
    pool.totalVolumeB = pool.totalVolumeB.plus(amtIn);
  }
  pool.updatedAt = event.block.timestamp;
  pool.save();

  let swapId = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let swap   = new Swap(swapId);
  swap.pool       = pool.id;
  swap.sender     = event.params.sender;
  swap.recipient  = event.params.recipient;
  swap.amountIn   = amtIn;
  swap.amountOut  = amtOut;
  swap.aToB       = event.params.aToB;
  swap.timestamp  = event.block.timestamp;
  swap.blockNumber = event.block.number;
  swap.txHash     = event.transaction.hash;
  swap.save();

  // Day data
  let day = loadOrCreateDayData(event.block.timestamp);
  day.dailySwaps = day.dailySwaps.plus(BigInt.fromI32(1));
  if (event.params.aToB) {
    day.dailyVolumeA = day.dailyVolumeA.plus(amtIn);
  } else {
    day.dailyVolumeB = day.dailyVolumeB.plus(amtIn);
  }
  day.save();
}

export function handleLiquidityAdded(event: LiquidityAdded): void {
  let pool = loadOrCreatePool(event.address);
  if (pool.createdAt.equals(BigInt.zero())) {
    pool.createdAt = event.block.timestamp;
  }
  pool.updatedAt = event.block.timestamp;
  pool.save();

  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let liq = new LiquidityEvent(id);
  liq.pool      = pool.id;
  liq.provider  = event.params.provider;
  liq.amountA   = toDecimal(event.params.amountA);
  liq.amountB   = toDecimal(event.params.amountB);
  liq.lpAmount  = toDecimal(event.params.lpMinted);
  liq.isAdd     = true;
  liq.timestamp = event.block.timestamp;
  liq.blockNumber = event.block.number;
  liq.txHash    = event.transaction.hash;
  liq.save();
}

export function handleLiquidityRemoved(event: LiquidityRemoved): void {
  let pool = loadOrCreatePool(event.address);
  pool.updatedAt = event.block.timestamp;
  pool.save();

  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let liq = new LiquidityEvent(id);
  liq.pool      = pool.id;
  liq.provider  = event.params.provider;
  liq.amountA   = toDecimal(event.params.amountA);
  liq.amountB   = toDecimal(event.params.amountB);
  liq.lpAmount  = toDecimal(event.params.lpBurned);
  liq.isAdd     = false;
  liq.timestamp = event.block.timestamp;
  liq.blockNumber = event.block.number;
  liq.txHash    = event.transaction.hash;
  liq.save();
}
