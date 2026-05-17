import { useAccount, useChainId, useReadContract, useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import { getDeployment } from "../config";
import { GOV_TOKEN_ABI, AMM_ABI, LENDING_ABI, VAULT_ABI, ERC20_ABI } from "../abis";

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────
export function useDeployment() {
  const chainId = useChainId();
  return getDeployment(chainId);
}

export function fmt(raw: bigint | undefined, decimals = 18, dp = 4): string {
  if (raw === undefined) return "—";
  return Number(formatUnits(raw, decimals)).toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: dp,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Governance token
// ─────────────────────────────────────────────────────────────────────────────
export function useGovTokenData() {
  const { address } = useAccount();
  const d           = useDeployment();

  const contract = { address: d?.govToken as `0x${string}`, abi: GOV_TOKEN_ABI } as const;

  const { data, isLoading, refetch } = useReadContracts({
    contracts: address && d
      ? [
          { ...contract, functionName: "balanceOf",    args: [address] },
          { ...contract, functionName: "getVotes",     args: [address] },
          { ...contract, functionName: "delegates",    args: [address] },
          { ...contract, functionName: "totalSupply"                  },
          { ...contract, functionName: "maxSupply"                    },
        ]
      : [],
    query: { enabled: !!address && !!d },
  });

  return {
    balance:    data?.[0]?.result as bigint | undefined,
    votes:      data?.[1]?.result as bigint | undefined,
    delegate:   data?.[2]?.result as string | undefined,
    totalSupply:data?.[3]?.result as bigint | undefined,
    maxSupply:  data?.[4]?.result as bigint | undefined,
    isLoading,
    refetch,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// AMM pool
// ─────────────────────────────────────────────────────────────────────────────
export function usePoolData() {
  const d = useDeployment();

  const contract = { address: d?.amm as `0x${string}`, abi: AMM_ABI } as const;

  const { data, isLoading, refetch } = useReadContracts({
    contracts: d
      ? [
          { ...contract, functionName: "getReserves" },
          { ...contract, functionName: "paused"      },
          { ...contract, functionName: "tokenA"      },
          { ...contract, functionName: "tokenB"      },
        ]
      : [],
    query: { enabled: !!d, refetchInterval: 12_000 },
  });

  const reserves = data?.[0]?.result as [bigint, bigint, number] | undefined;

  return {
    reserveA:  reserves?.[0],
    reserveB:  reserves?.[1],
    paused:    data?.[1]?.result as boolean | undefined,
    tokenA:    data?.[2]?.result as string  | undefined,
    tokenB:    data?.[3]?.result as string  | undefined,
    isLoading,
    refetch,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Lending position
// ─────────────────────────────────────────────────────────────────────────────
export function useLendingPosition() {
  const { address } = useAccount();
  const d           = useDeployment();

  const contract = { address: d?.lending as `0x${string}`, abi: LENDING_ABI } as const;

  const { data, isLoading, refetch } = useReadContracts({
    contracts: address && d
      ? [
          { ...contract, functionName: "positions",      args: [address] },
          { ...contract, functionName: "healthFactor",   args: [address] },
          { ...contract, functionName: "currentDebt",    args: [address] },
          { ...contract, functionName: "utilizationRate"                  },
          { ...contract, functionName: "totalCollateral"                  },
          { ...contract, functionName: "totalDebt"                        },
        ]
      : [],
    query: { enabled: !!address && !!d, refetchInterval: 15_000 },
  });

  const pos = data?.[0]?.result as [bigint, bigint, bigint, number] | undefined;

  return {
    collateral:       pos?.[0],
    debtPrincipal:    pos?.[1],
    positionState:    pos?.[3], // 0=None,1=Active,2=Liquidated
    healthFactor:     data?.[1]?.result as bigint | undefined,
    currentDebt:      data?.[2]?.result as bigint | undefined,
    utilizationRate:  data?.[3]?.result as bigint | undefined,
    totalCollateral:  data?.[4]?.result as bigint | undefined,
    totalDebt:        data?.[5]?.result as bigint | undefined,
    isLoading,
    refetch,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Vault
// ─────────────────────────────────────────────────────────────────────────────
export function useVaultData() {
  const { address } = useAccount();
  const d           = useDeployment();

  const contract = { address: d?.vault as `0x${string}`, abi: VAULT_ABI } as const;

  const { data, isLoading, refetch } = useReadContracts({
    contracts: d
      ? [
          { ...contract, functionName: "totalAssets"  },
          { ...contract, functionName: "totalSupply"  },
          ...(address
            ? [
                { ...contract, functionName: "balanceOf",       args: [address] } as const,
                { ...contract, functionName: "convertToAssets", args: [data?.[2]?.result as bigint ?? 0n] } as const,
              ]
            : []),
        ]
      : [],
    query: { enabled: !!d, refetchInterval: 15_000 },
  });

  const shares      = data?.[2]?.result as bigint | undefined;
  const totalAssets = data?.[0]?.result as bigint | undefined;
  const totalSupply = data?.[1]?.result as bigint | undefined;

  const sharePrice =
    totalSupply && totalSupply > 0n && totalAssets
      ? (totalAssets * 10n ** 18n) / totalSupply
      : 10n ** 18n;

  return { totalAssets, totalSupply, shares, sharePrice, isLoading, refetch };
}

// ─────────────────────────────────────────────────────────────────────────────
// Token balance helper
// ─────────────────────────────────────────────────────────────────────────────
export function useTokenBalance(tokenAddress: string | undefined) {
  const { address } = useAccount();

  return useReadContract({
    address: tokenAddress as `0x${string}`,
    abi:     ERC20_ABI,
    functionName: "balanceOf",
    args:    address ? [address] : undefined,
    query:   { enabled: !!tokenAddress && !!address, refetchInterval: 15_000 },
  });
}
