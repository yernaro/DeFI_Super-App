import { BigDecimal, BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  CollateralDeposited,
  CollateralWithdrawn,
  Borrowed,
  Repaid,
  Liquidated,
} from "../generated/LendingPool/LendingPool";
import {
  LendingPosition,
  CollateralEvent,
  BorrowEvent,
  RepayEvent,
  Liquidation,
  ProtocolDayData,
} from "../generated/schema";

const EIGHTEEN = BigDecimal.fromString("1000000000000000000");

function toDecimal(raw: BigInt): BigDecimal {
  return raw.toBigDecimal().div(EIGHTEEN);
}

function loadOrCreatePosition(user: Bytes, timestamp: BigInt): LendingPosition {
  let id = user.toHexString();
  let pos = LendingPosition.load(id);
  if (!pos) {
    pos = new LendingPosition(id);
    pos.user             = user;
    pos.collateralAmount = BigDecimal.zero();
    pos.debtAmount       = BigDecimal.zero();
    pos.state            = "None";
    pos.createdAt        = timestamp;
    pos.updatedAt        = timestamp;
  }
  return pos;
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

// ─────────────────────────────────────────────────────────────────────────────
export function handleCollateralDeposited(event: CollateralDeposited): void {
  let pos = loadOrCreatePosition(event.params.user, event.block.timestamp);
  pos.collateralAmount = pos.collateralAmount.plus(toDecimal(event.params.amount));
  pos.state            = "Active";
  pos.updatedAt        = event.block.timestamp;
  pos.save();

  let id  = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let evt = new CollateralEvent(id);
  evt.position  = pos.id;
  evt.amount    = toDecimal(event.params.amount);
  evt.isDeposit = true;
  evt.timestamp = event.block.timestamp;
  evt.txHash    = event.transaction.hash;
  evt.save();
}

export function handleCollateralWithdrawn(event: CollateralWithdrawn): void {
  let pos = loadOrCreatePosition(event.params.user, event.block.timestamp);
  pos.collateralAmount = pos.collateralAmount.minus(toDecimal(event.params.amount));
  pos.updatedAt        = event.block.timestamp;
  pos.save();

  let id  = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let evt = new CollateralEvent(id);
  evt.position  = pos.id;
  evt.amount    = toDecimal(event.params.amount);
  evt.isDeposit = false;
  evt.timestamp = event.block.timestamp;
  evt.txHash    = event.transaction.hash;
  evt.save();
}

export function handleBorrowed(event: Borrowed): void {
  let pos = loadOrCreatePosition(event.params.user, event.block.timestamp);
  pos.debtAmount = pos.debtAmount.plus(toDecimal(event.params.amount));
  pos.updatedAt  = event.block.timestamp;
  pos.save();

  let id  = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let evt = new BorrowEvent(id);
  evt.position  = pos.id;
  evt.amount    = toDecimal(event.params.amount);
  evt.timestamp = event.block.timestamp;
  evt.txHash    = event.transaction.hash;
  evt.save();
}

export function handleRepaid(event: Repaid): void {
  let pos = loadOrCreatePosition(event.params.user, event.block.timestamp);
  let repaid   = toDecimal(event.params.amount);
  let interest = toDecimal(event.params.interest);
  // debtAmount tracks principal; interest comes on top
  let principal = repaid.minus(interest);
  if (pos.debtAmount.ge(principal)) {
    pos.debtAmount = pos.debtAmount.minus(principal);
  } else {
    pos.debtAmount = BigDecimal.zero();
  }
  pos.updatedAt = event.block.timestamp;
  pos.save();

  let id  = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let evt = new RepayEvent(id);
  evt.position  = pos.id;
  evt.amount    = repaid;
  evt.interest  = interest;
  evt.timestamp = event.block.timestamp;
  evt.txHash    = event.transaction.hash;
  evt.save();
}

export function handleLiquidated(event: Liquidated): void {
  let borrowerPos = loadOrCreatePosition(event.params.borrower, event.block.timestamp);
  let debtRepaid  = toDecimal(event.params.debtRepaid);
  let colSeized   = toDecimal(event.params.collateralSeized);

  borrowerPos.debtAmount       = borrowerPos.debtAmount.minus(debtRepaid);
  borrowerPos.collateralAmount = borrowerPos.collateralAmount.minus(colSeized);
  if (borrowerPos.debtAmount.le(BigDecimal.zero())) {
    borrowerPos.debtAmount = BigDecimal.zero();
    borrowerPos.state      = "Liquidated";
  }
  borrowerPos.updatedAt = event.block.timestamp;
  borrowerPos.save();

  let id  = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let liq = new Liquidation(id);
  liq.liquidator       = event.params.liquidator;
  liq.borrower         = borrowerPos.id;
  liq.debtRepaid       = debtRepaid;
  liq.collateralSeized = colSeized;
  liq.timestamp        = event.block.timestamp;
  liq.blockNumber      = event.block.number;
  liq.txHash           = event.transaction.hash;
  liq.save();

  let day = loadOrCreateDayData(event.block.timestamp);
  day.dailyLiquidations = day.dailyLiquidations.plus(BigInt.fromI32(1));
  day.save();
}
