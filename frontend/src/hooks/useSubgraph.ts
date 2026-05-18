import { useQuery } from "@tanstack/react-query";
import { useChainId } from "wagmi";
import { getDeployment } from "../config";


const PROPOSALS_QUERY = `
  query ActiveProposals {
    proposals(
      orderBy: createdAt
      orderDirection: desc
      first: 20
    ) {
      id
      proposer
      description
      state
      forVotes
      againstVotes
      abstainVotes
      startBlock
      endBlock
      eta
      executedAt
      createdAt
    }
  }
`;

const RECENT_SWAPS_QUERY = `
  query RecentSwaps {
    swaps(orderBy: timestamp, orderDirection: desc, first: 50) {
      id
      sender
      recipient
      amountIn
      amountOut
      aToB
      timestamp
      txHash
      pool {
        id
        reserveA
        reserveB
      }
    }
  }
`;

const AT_RISK_POSITIONS_QUERY = `
  query AtRiskPositions {
    lendingPositions(
      where: { state: "Active", debtAmount_gt: "0" }
      orderBy: debtAmount
      orderDirection: desc
      first: 20
    ) {
      id
      user
      collateralAmount
      debtAmount
      state
      updatedAt
    }
  }
`;

const PROTOCOL_STATS_QUERY = `
  query ProtocolDailyStats {
    protocolDayDatas(orderBy: date, orderDirection: desc, first: 30) {
      id
      date
      dailyVolumeA
      dailyVolumeB
      dailySwaps
      dailyLiquidations
      dailyVaultDeposits
      dailyYieldHarvested
    }
  }
`;

const VOTER_HISTORY_QUERY = `
  query VoterHistory($voter: Bytes!) {
    votes(
      where: { voter: $voter }
      orderBy: timestamp
      orderDirection: desc
      first: 50
    ) {
      id
      proposal { id description state }
      support
      weight
      reason
      timestamp
      txHash
    }
  }
`;




async function gqlFetch<T>(
  url: string,
  query: string,
  variables?: Record<string, unknown>,
): Promise<T> {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query, variables }),
  });
  if (!res.ok) throw new Error(`GraphQL HTTP error: ${res.status}`);
  const json = await res.json();
  if (json.errors?.length) throw new Error(json.errors[0].message);
  return json.data as T;
}





function useSubgraphUrl(): string | null {
  const chainId = useChainId();
  const d = getDeployment(chainId);
  return d?.subgraph ?? null;
}

export function useProposals() {
  const url = useSubgraphUrl();
  return useQuery({
    queryKey: ["proposals", url],
    queryFn: () => gqlFetch<{ proposals: Proposal[] }>(url!, PROPOSALS_QUERY),
    enabled: !!url,
    refetchInterval: 30_000,
  });
}

export function useRecentSwaps() {
  const url = useSubgraphUrl();
  return useQuery({
    queryKey: ["swaps", url],
    queryFn: () =>
      gqlFetch<{ swaps: SubgraphSwap[] }>(url!, RECENT_SWAPS_QUERY),
    enabled: !!url,
    refetchInterval: 20_000,
  });
}

export function useAtRiskPositions() {
  const url = useSubgraphUrl();
  return useQuery({
    queryKey: ["atRiskPositions", url],
    queryFn: () =>
      gqlFetch<{ lendingPositions: SubgraphPosition[] }>(
        url!,
        AT_RISK_POSITIONS_QUERY,
      ),
    enabled: !!url,
    refetchInterval: 30_000,
  });
}

export function useProtocolStats() {
  const url = useSubgraphUrl();
  return useQuery({
    queryKey: ["protocolStats", url],
    queryFn: () =>
      gqlFetch<{ protocolDayDatas: DayData[] }>(url!, PROTOCOL_STATS_QUERY),
    enabled: !!url,
    refetchInterval: 60_000,
  });
}

export function useVoterHistory(voter: string | undefined) {
  const url = useSubgraphUrl();
  return useQuery({
    queryKey: ["voterHistory", url, voter],
    queryFn: () =>
      gqlFetch<{ votes: SubgraphVote[] }>(url!, VOTER_HISTORY_QUERY, { voter }),
    enabled: !!url && !!voter,
  });
}


export interface Proposal {
  id: string;
  proposer: string;
  description: string;
  state: string;
  forVotes: string;
  againstVotes: string;
  abstainVotes: string;
  startBlock: string;
  endBlock: string;
  eta: string | null;
  executedAt: string | null;
  createdAt: string;
}

export interface SubgraphSwap {
  id: string;
  sender: string;
  recipient: string;
  amountIn: string;
  amountOut: string;
  aToB: boolean;
  timestamp: string;
  txHash: string;
  pool: { id: string; reserveA: string; reserveB: string };
}

export interface SubgraphPosition {
  id: string;
  user: string;
  collateralAmount: string;
  debtAmount: string;
  state: string;
  updatedAt: string;
}

export interface DayData {
  id: string;
  date: number;
  dailyVolumeA: string;
  dailyVolumeB: string;
  dailySwaps: string;
  dailyLiquidations: string;
  dailyVaultDeposits: string;
  dailyYieldHarvested: string;
}

export interface SubgraphVote {
  id: string;
  proposal: { id: string; description: string; state: string };
  support: number;
  weight: string;
  reason: string | null;
  timestamp: string;
  txHash: string;
}
