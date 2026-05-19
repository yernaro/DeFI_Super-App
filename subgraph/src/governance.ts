import { BigDecimal, BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  ProposalCreated,
  VoteCast,
  ProposalQueued,
  ProposalExecuted,
  ProposalCanceled,
} from "../generated/DeFiGovernor/DeFiGovernor";
import { Proposal, Vote, GovernanceStats } from "../generated/schema";

const EIGHTEEN = BigDecimal.fromString("1000000000000000000");
function toDecimal(raw: BigInt): BigDecimal {
  return raw.toBigDecimal().div(EIGHTEEN);
}

function loadOrCreateStats(): GovernanceStats {
  let stats = GovernanceStats.load("governance");
  if (!stats) {
    stats = new GovernanceStats("governance");
    stats.totalProposals   = BigInt.zero();
    stats.totalVotesCast   = BigInt.zero();
    stats.totalVotingPower = BigDecimal.zero();
    stats.uniqueVoters     = BigInt.zero();
  }
  return stats;
}

export function handleProposalCreated(event: ProposalCreated): void {
  let id       = event.params.proposalId.toString();
  let proposal = new Proposal(id);
  proposal.proposer      = event.params.proposer;
  proposal.description   = event.params.description;
  proposal.startBlock    = event.params.voteStart;
  proposal.endBlock      = event.params.voteEnd;
  proposal.state         = "Pending";
  proposal.forVotes      = BigDecimal.zero();
  proposal.againstVotes  = BigDecimal.zero();
  proposal.abstainVotes  = BigDecimal.zero();
  proposal.createdAt     = event.block.timestamp;
  proposal.save();

  let stats = loadOrCreateStats();
  stats.totalProposals = stats.totalProposals.plus(BigInt.fromI32(1));
  stats.save();
}

export function handleVoteCast(event: VoteCast): void {
  let proposalId = event.params.proposalId.toString();
  let proposal   = Proposal.load(proposalId);
  if (!proposal) return;

  proposal.state = "Active";
  let weight = toDecimal(event.params.weight);

  if (event.params.support == 0) {
    proposal.againstVotes = proposal.againstVotes.plus(weight);
  } else if (event.params.support == 1) {
    proposal.forVotes = proposal.forVotes.plus(weight);
  } else {
    proposal.abstainVotes = proposal.abstainVotes.plus(weight);
  }
  proposal.save();

  let voteId = proposalId + "-" + event.params.voter.toHexString();
  let vote   = new Vote(voteId);
  vote.proposal   = proposalId;
  vote.voter      = event.params.voter;
  vote.support    = event.params.support;
  vote.weight     = weight;
  vote.reason     = event.params.reason;
  vote.timestamp  = event.block.timestamp;
  vote.txHash     = event.transaction.hash;
  vote.save();

  let stats = loadOrCreateStats();
  stats.totalVotesCast   = stats.totalVotesCast.plus(BigInt.fromI32(1));
  stats.totalVotingPower = stats.totalVotingPower.plus(weight);
  stats.save();
}

export function handleProposalQueued(event: ProposalQueued): void {
  let proposal = Proposal.load(event.params.proposalId.toString());
  if (!proposal) return;
  proposal.state = "Queued";
  proposal.eta   = event.params.etaSeconds;
  proposal.save();
}

export function handleProposalExecuted(event: ProposalExecuted): void {
  let proposal = Proposal.load(event.params.proposalId.toString());
  if (!proposal) return;
  proposal.state      = "Executed";
  proposal.executedAt = event.block.timestamp;
  proposal.save();
}

export function handleProposalCanceled(event: ProposalCanceled): void {
  let proposal = Proposal.load(event.params.proposalId.toString());
  if (!proposal) return;
  proposal.state      = "Canceled";
  proposal.canceledAt = event.block.timestamp;
  proposal.save();
}
