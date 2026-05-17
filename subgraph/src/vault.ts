// ── vault.ts ─────────────────────────────────────────────────────────────────
import { BigDecimal, BigInt } from "@graphprotocol/graph-ts";
import {
  Deposit,
  Withdraw,
  YieldHarvested,
} from "../../generated/YieldVault/YieldVault";
import {
  VaultDeposit,
  VaultWithdraw,
  YieldHarvest,
  ProtocolDayData,
} from "../../generated/schema";

const EIGHTEEN = BigDecimal.fromString("1000000000000000000");
function toDecimal(raw: BigInt): BigDecimal {
  return raw.toBigDecimal().div(EIGHTEEN);
}
function loadOrCreateDayData(timestamp: BigInt): ProtocolDayData {
  let dayId = timestamp.toI32() / 86400;
  let id    = dayId.toString();
  let data  = ProtocolDayData.load(id);
  if (!data) {
    data = new ProtocolDayData(id);
    data.date                = dayId;
    data.dailyVolumeA        = BigDecimal.zero();
    data.dailyVolumeB        = BigDecimal.zero();
    data.dailySwaps          = BigInt.zero();
    data.dailyLiquidations   = BigInt.zero();
    data.dailyVaultDeposits  = BigDecimal.zero();
    data.dailyYieldHarvested = BigDecimal.zero();
  }
  return data;
}

export function handleVaultDeposit(event: Deposit): void {
  let id  = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let dep = new VaultDeposit(id);
  dep.caller    = event.params.sender;
  dep.owner     = event.params.owner;
  dep.assets    = toDecimal(event.params.assets);
  dep.shares    = toDecimal(event.params.shares);
  dep.timestamp = event.block.timestamp;
  dep.txHash    = event.transaction.hash;
  dep.save();

  let day = loadOrCreateDayData(event.block.timestamp);
  day.dailyVaultDeposits = day.dailyVaultDeposits.plus(dep.assets);
  day.save();
}

export function handleVaultWithdraw(event: Withdraw): void {
  let id  = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let w   = new VaultWithdraw(id);
  w.caller    = event.params.sender;
  w.receiver  = event.params.receiver;
  w.owner     = event.params.owner;
  w.assets    = toDecimal(event.params.assets);
  w.shares    = toDecimal(event.params.shares);
  w.timestamp = event.block.timestamp;
  w.txHash    = event.transaction.hash;
  w.save();
}

export function handleYieldHarvested(event: YieldHarvested): void {
  let id  = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let h   = new YieldHarvest(id);
  h.grossAmount  = toDecimal(event.params.amount);
  h.feeAmount    = toDecimal(event.params.fee);
  h.feeRecipient = event.params.feeRecipient;
  h.timestamp    = event.block.timestamp;
  h.txHash       = event.transaction.hash;
  h.save();

  let day = loadOrCreateDayData(event.block.timestamp);
  day.dailyYieldHarvested = day.dailyYieldHarvested.plus(h.grossAmount);
  day.save();
}
