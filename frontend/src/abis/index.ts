import { parseAbi } from "viem";

const ERC20_ABI_ITEMS = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address,address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
  "function transfer(address,uint256) returns (bool)",
  "function transferFrom(address,address,uint256) returns (bool)",
] as const;

export const ERC20_ABI = parseAbi(ERC20_ABI_ITEMS);

export const GOV_TOKEN_ABI = parseAbi([
  ...ERC20_ABI_ITEMS,
  "function getVotes(address) view returns (uint256)",
  "function delegates(address) view returns (address)",
  "function delegate(address delegatee)",
  "function getPastVotes(address,uint256) view returns (uint256)",
  "function getPastTotalSupply(uint256) view returns (uint256)",
  "function maxSupply() view returns (uint256)",
  "event DelegateChanged(address indexed,address indexed,address indexed)",
  "event DelegateVotesChanged(address indexed,uint256,uint256)",
] as const);

export const AMM_ABI = parseAbi([
  "function tokenA() view returns (address)",
  "function tokenB() view returns (address)",
  "function lpToken() view returns (address)",
  "function getReserves() view returns (uint112,uint112,uint32)",
  "function getAmountOut(uint256,uint256,uint256) view returns (uint256)",
  "function getAmountIn(uint256,uint256,uint256) view returns (uint256)",
  "function addLiquidity(uint256,uint256,uint256,uint256) returns (uint256,uint256,uint256)",
  "function removeLiquidity(uint256,uint256,uint256) returns (uint256,uint256)",
  "function swap(uint256,uint256,bool,address) returns (uint256)",
  "function paused() view returns (bool)",
  "event LiquidityAdded(address indexed,uint256,uint256,uint256)",
  "event LiquidityRemoved(address indexed,uint256,uint256,uint256)",
  "event Swap(address indexed,uint256,uint256,bool,address indexed)",
  "event Sync(uint112,uint112)",
] as const);

export const LENDING_ABI = parseAbi([
  "function positions(address) view returns (uint256,uint256,uint256,uint8)",
  "function healthFactor(address) view returns (uint256)",
  "function currentDebt(address) view returns (uint256)",
  "function utilizationRate() view returns (uint256)",
  "function totalCollateral() view returns (uint256)",
  "function totalDebt() view returns (uint256)",
  "function depositCollateral(uint256)",
  "function withdrawCollateral(uint256)",
  "function borrow(uint256)",
  "function repay(uint256)",
  "function liquidate(address,uint256)",
  "function supplyDebtToken(uint256)",
  "event CollateralDeposited(address indexed,uint256)",
  "event CollateralWithdrawn(address indexed,uint256)",
  "event Borrowed(address indexed,uint256)",
  "event Repaid(address indexed,uint256,uint256)",
  "event Liquidated(address indexed,address indexed,uint256,uint256)",
] as const);

export const VAULT_ABI = parseAbi([
  "function asset() view returns (address)",
  "function totalAssets() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function convertToShares(uint256) view returns (uint256)",
  "function convertToAssets(uint256) view returns (uint256)",
  "function previewDeposit(uint256) view returns (uint256)",
  "function previewRedeem(uint256) view returns (uint256)",
  "function deposit(uint256,address) returns (uint256)",
  "function withdraw(uint256,address,address) returns (uint256)",
  "function redeem(uint256,address,address) returns (uint256)",
  "function performanceFee() view returns (uint256)",
  "event Deposit(address indexed,address indexed,uint256,uint256)",
  "event Withdraw(address indexed,address indexed,address indexed,uint256,uint256)",
] as const);

export const GOVERNOR_ABI = parseAbi([
  "function name() view returns (string)",
  "function votingDelay() view returns (uint256)",
  "function votingPeriod() view returns (uint256)",
  "function quorumNumerator() view returns (uint256)",
  "function proposalThreshold() view returns (uint256)",
  "function state(uint256) view returns (uint8)",
  "function proposalSnapshot(uint256) view returns (uint256)",
  "function proposalDeadline(uint256) view returns (uint256)",
  "function proposalVotes(uint256) view returns (uint256,uint256,uint256)",
  "function hasVoted(uint256,address) view returns (bool)",
  "function propose(address[],uint256[],bytes[],string) returns (uint256)",
  "function castVote(uint256,uint8) returns (uint256)",
  "function castVoteWithReason(uint256,uint8,string) returns (uint256)",
  "function queue(address[],uint256[],bytes[],bytes32) returns (uint256)",
  "function execute(address[],uint256[],bytes[],bytes32) returns (uint256)",
  "event ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)",
  "event VoteCast(address indexed,uint256,uint8,uint256,string)",
  "event ProposalQueued(uint256,uint256)",
  "event ProposalExecuted(uint256)",
] as const);
