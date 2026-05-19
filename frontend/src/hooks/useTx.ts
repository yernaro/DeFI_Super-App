import { useState, useCallback } from "react";
import {
  useAccount,
  useChainId,
  usePublicClient,
  useWriteContract,
  useWaitForTransactionReceipt,
  useSwitchChain,
} from "wagmi";
import { parseUnits, parseEther } from "viem";
import { getDeployment, SUPPORTED_CHAINS } from "../config";
import {
  AMM_ABI,
  LENDING_ABI,
  VAULT_ABI,
  GOV_TOKEN_ABI,
  GOVERNOR_ABI,
  ERC20_ABI,
} from "../abis";

// ─────────────────────────────────────────────────────────────────────────────
// Error parser — converts RPC / contract errors to human-readable strings
// ─────────────────────────────────────────────────────────────────────────────
export function parseError(err: unknown): string {
  if (!err) return "Unknown error";
  const msg = String(
    (err as { shortMessage?: string; message?: string })?.shortMessage ||
      (err as { message?: string })?.message ||
      err,
  );

  if (msg.includes("rejected") || msg.includes("denied"))
    return "Transaction rejected by user.";
  if (msg.includes("insufficient funds")) return "Insufficient ETH for gas.";
  if (msg.includes("InsufficientLiquidity"))
    return "Insufficient liquidity in pool.";
  if (msg.includes("SlippageExceeded"))
    return "Slippage tolerance exceeded. Try increasing slippage.";
  if (msg.includes("ExceedsLTV")) return "Borrow amount exceeds LTV limit.";
  if (msg.includes("HealthyPosition"))
    return "Position is healthy — cannot liquidate.";
  if (msg.includes("SupplyCapExceeded"))
    return "Governance token supply cap exceeded.";
  if (msg.includes("ZeroAmount")) return "Amount must be greater than zero.";
  if (msg.includes("wrong network") || msg.includes("chain"))
    return "Wrong network — please switch chain.";
  return msg.length > 120 ? msg.slice(0, 120) + "…" : msg;
}

// ─────────────────────────────────────────────────────────────────────────────
// Network guard
// ─────────────────────────────────────────────────────────────────────────────
export function useNetworkGuard() {
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();
  const supported = SUPPORTED_CHAINS.map((c) => c.id);
  const isSupported = supported.includes(chainId as (typeof supported)[number]);

  const promptSwitch = useCallback(() => {
    switchChain({ chainId: SUPPORTED_CHAINS[0].id });
  }, [switchChain]);

  return { isSupported, promptSwitch };
}

// ─────────────────────────────────────────────────────────────────────────────
// Generic write hook wrapper
// ─────────────────────────────────────────────────────────────────────────────
export function useTx() {
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const { writeContractAsync } = useWriteContract();
  const { address } = useAccount();
  const publicClient = usePublicClient();

  const write = useCallback(
    async (
      args: Parameters<typeof writeContractAsync>[0],
    ): Promise<`0x${string}` | null> => {
      setError(null);
      setPending(true);
      try {
        const fees = await publicClient?.estimateFeesPerGas().catch(() => null);
        const block = await publicClient?.getBlock().catch(() => null);
        const gas = address
          ? await publicClient
              ?.estimateContractGas({ ...args, account: address })
              .catch(() => null)
          : null;
        const baseFee = block?.baseFeePerGas;
        const minPriorityFee = 1_000_000n;
        const priorityFee = fees?.maxPriorityFeePerGas
          ? fees.maxPriorityFeePerGas > minPriorityFee
            ? fees.maxPriorityFeePerGas
            : minPriorityFee
          : minPriorityFee;
        const maxFee = baseFee
          ? baseFee * 3n + priorityFee
          : fees?.maxFeePerGas
            ? (fees.maxFeePerGas * 150n) / 100n
            : undefined;
        const bufferedArgs =
          maxFee
            ? {
                ...args,
                gas: gas ? (gas * 150n) / 100n : undefined,
                maxFeePerGas: maxFee,
                maxPriorityFeePerGas: priorityFee,
              }
            : args;
        const hash = await writeContractAsync(bufferedArgs);
        await publicClient?.waitForTransactionReceipt({ hash });
        return hash;
      } catch (err) {
        setError(parseError(err));
        return null;
      } finally {
        setPending(false);
      }
    },
    [publicClient, writeContractAsync],
  );

  return { write, pending, error, clearError: () => setError(null) };
}

// ─────────────────────────────────────────────────────────────────────────────
// AMM transactions
// ─────────────────────────────────────────────────────────────────────────────
export function useSwap() {
  const chainId = useChainId();
  const { write, pending, error } = useTx();
  const d = getDeployment(chainId);

  const swap = useCallback(
    async (
      amountIn: string,
      minAmountOut: string,
      aToB: boolean,
      recipient: string,
    ) => {
      if (!d) return null;
      // First approve tokenIn
      const tokenIn = aToB ? d.tokenA : d.tokenB;
      const approved = await write({
        address: tokenIn as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [d.amm as `0x${string}`, parseUnits(amountIn, 18)],
      });
      if (!approved) return null;
      return write({
        address: d.amm as `0x${string}`,
        abi: AMM_ABI,
        functionName: "swap",
        args: [
          parseUnits(amountIn, 18),
          parseUnits(minAmountOut, 18),
          !aToB,
          recipient as `0x${string}`,
        ],
      });
    },
    [d, write],
  );

  return { swap, pending, error };
}

export function useAddLiquidity() {
  const chainId = useChainId();
  const { write, pending, error } = useTx();
  const d = getDeployment(chainId);

  const addLiquidity = useCallback(
    async (amtA: string, amtB: string) => {
      if (!d) return null;
      const amtAWei = parseUnits(amtA, 18);
      const amtBWei = parseUnits(amtB, 18);
      const slippage = 50n; // 0.5 %
      const minA = (amtAWei * (10000n - slippage)) / 10000n;
      const minB = (amtBWei * (10000n - slippage)) / 10000n;

      const approvedA = await write({
        address: d.tokenA as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [d.amm as `0x${string}`, amtAWei],
      });
      if (!approvedA) return null;
      const approvedB = await write({
        address: d.tokenB as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [d.amm as `0x${string}`, amtBWei],
      });
      if (!approvedB) return null;

      return write({
        address: d.amm as `0x${string}`,
        abi: AMM_ABI,
        functionName: "addLiquidity",
        args: [amtBWei, amtAWei, minB, minA],
      });
    },
    [d, write],
  );

  return { addLiquidity, pending, error };
}

// ─────────────────────────────────────────────────────────────────────────────
// Lending transactions
// ─────────────────────────────────────────────────────────────────────────────
export function useLendingTx() {
  const chainId = useChainId();
  const { write, pending, error } = useTx();
  const d = getDeployment(chainId);

  const depositCollateral = useCallback(
    async (amount: string) => {
      if (!d) return null;
      const wei = parseUnits(amount, 18);
      const approved = await write({
        address: d.tokenA as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [d.lending as `0x${string}`, wei],
      });
      if (!approved) return null;
      return write({
        address: d.lending as `0x${string}`,
        abi: LENDING_ABI,
        functionName: "depositCollateral",
        args: [wei],
      });
    },
    [d, write],
  );

  const borrow = useCallback(
    async (amount: string) => {
      if (!d) return null;
      return write({
        address: d.lending as `0x${string}`,
        abi: LENDING_ABI,
        functionName: "borrow",
        args: [parseUnits(amount, 18)],
      });
    },
    [d, write],
  );

  const repay = useCallback(
    async (amount: string) => {
      if (!d) return null;
      const wei = parseUnits(amount, 18);
      const approved = await write({
        address: d.tokenB as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [d.lending as `0x${string}`, wei],
      });
      if (!approved) return null;
      return write({
        address: d.lending as `0x${string}`,
        abi: LENDING_ABI,
        functionName: "repay",
        args: [wei],
      });
    },
    [d, write],
  );

  const supplyDebtToken = useCallback(
    async (amount: string) => {
      if (!d) return null;
      const wei = parseUnits(amount, 18);
      const approved = await write({
        address: d.tokenB as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [d.lending as `0x${string}`, wei],
      });
      if (!approved) return null;
      return write({
        address: d.lending as `0x${string}`,
        abi: LENDING_ABI,
        functionName: "supplyDebtToken",
        args: [wei],
      });
    },
    [d, write],
  );

  return { depositCollateral, borrow, repay, supplyDebtToken, pending, error };
}

// ─────────────────────────────────────────────────────────────────────────────
// Vault transactions
// ─────────────────────────────────────────────────────────────────────────────
export function useVaultTx() {
  const chainId = useChainId();
  const { write, pending, error } = useTx();
  const d = getDeployment(chainId);
  const { address } = useAccount();

  const deposit = useCallback(
    async (amount: string) => {
      if (!d || !address) return null;
      const wei = parseUnits(amount, 18);
      const approved = await write({
        address: d.tokenB as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [d.vault as `0x${string}`, wei],
      });
      if (!approved) return null;
      return write({
        address: d.vault as `0x${string}`,
        abi: VAULT_ABI,
        functionName: "deposit",
        args: [wei, address],
      });
    },
    [d, address, write],
  );

  const redeem = useCallback(
    async (shares: bigint) => {
      if (!d || !address) return null;
      return write({
        address: d.vault as `0x${string}`,
        abi: VAULT_ABI,
        functionName: "redeem",
        args: [shares, address, address],
      });
    },
    [d, address, write],
  );

  return { deposit, redeem, pending, error };
}

// ─────────────────────────────────────────────────────────────────────────────
// Governance transactions
// ─────────────────────────────────────────────────────────────────────────────
export function useGovernanceTx() {
  const chainId = useChainId();
  const { write, pending, error } = useTx();
  const d = getDeployment(chainId);

  const delegate = useCallback(
    async (delegatee: string) => {
      if (!d) return null;
      return write({
        address: d.govToken as `0x${string}`,
        abi: GOV_TOKEN_ABI,
        functionName: "delegate",
        args: [delegatee as `0x${string}`],
      });
    },
    [d, write],
  );

  const castVote = useCallback(
    async (proposalId: bigint, support: number, reason?: string) => {
      if (!d) return null;
      if (reason) {
        return write({
          address: d.governor as `0x${string}`,
          abi: GOVERNOR_ABI,
          functionName: "castVoteWithReason",
          args: [proposalId, support, reason],
        });
      }
      return write({
        address: d.governor as `0x${string}`,
        abi: GOVERNOR_ABI,
        functionName: "castVote",
        args: [proposalId, support],
      });
    },
    [d, write],
  );

  return { delegate, castVote, pending, error };
}
