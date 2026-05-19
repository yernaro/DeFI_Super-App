import React, { useState, useEffect } from "react";
import {
  WagmiProvider,
  useAccount,
  useConnect,
  useDisconnect,
  useChainId,
} from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { formatUnits, parseUnits } from "viem";
import { config, SUPPORTED_CHAINS, getDeployment } from "./config";
import {
  useGovTokenData,
  usePoolData,
  useLendingPosition,
  useVaultData,
  useTokenBalance,
  fmt,
} from "./hooks/useProtocol";
import {
  useProposals,
  useRecentSwaps,
  useProtocolStats,
} from "./hooks/useSubgraph";
import {
  useSwap,
  useAddLiquidity,
  useLendingTx,
  useVaultTx,
  useGovernanceTx,
  useNetworkGuard,
  parseError,
} from "./hooks/useTx";

const queryClient = new QueryClient();

const STATE_COLORS: Record<string, string> = {
  Pending: "#f59e0b",
  Active: "#10b981",
  Succeeded: "#6366f1",
  Defeated: "#ef4444",
  Queued: "#8b5cf6",
  Executed: "#06b6d4",
  Canceled: "#6b7280",
};

function StateBadge({ state }: { state: string }) {
  return (
    <span
      style={{
        background: STATE_COLORS[state] || "#6b7280",
        color: "#fff",
        padding: "2px 10px",
        borderRadius: 999,
        fontSize: 12,
        fontWeight: 700,
      }}
    >
      {state}
    </span>
  );
}

function shortAddr(addr: string) {
  return addr ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : "—";
}

function ErrorBanner({ msg, onClose }: { msg: string; onClose: () => void }) {
  return (
    <div
      style={{
        background: "#fef2f2",
        border: "1px solid #fca5a5",
        borderRadius: 8,
        padding: "10px 16px",
        margin: "8px 0",
        display: "flex",
        justifyContent: "space-between",
        alignItems: "center",
      }}
    >
      <span style={{ color: "#b91c1c", fontSize: 14 }}>⚠️ {msg}</span>
      <button
        onClick={onClose}
        style={{
          background: "none",
          border: "none",
          cursor: "pointer",
          color: "#6b7280",
        }}
      >
        ✕
      </button>
    </div>
  );
}

function NetworkBanner() {
  const { isSupported, promptSwitch } = useNetworkGuard();
  const chainId = useChainId();
  if (isSupported) return null;
  return (
    <div
      style={{
        background: "#fef3c7",
        border: "1px solid #fcd34d",
        borderRadius: 8,
        padding: "10px 16px",
        margin: "8px 0",
        display: "flex",
        justifyContent: "space-between",
        alignItems: "center",
      }}
    >
      <span style={{ color: "#92400e", fontSize: 14 }}>
        🔗 Wrong network (chainId: {chainId}). Please switch to
        Arbitrum/Optimism/Base Sepolia.
      </span>
      <button
        onClick={promptSwitch}
        style={{
          background: "#f59e0b",
          border: "none",
          borderRadius: 6,
          padding: "4px 12px",
          cursor: "pointer",
          color: "#fff",
          fontWeight: 700,
        }}
      >
        Switch
      </button>
    </div>
  );
}

function WalletBar() {
  const { address, isConnected } = useAccount();
  const { connect, connectors } = useConnect();
  const { disconnect } = useDisconnect();
  const chainId = useChainId();
  const chain = SUPPORTED_CHAINS.find((c) => c.id === chainId);

  if (isConnected) {
    return (
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <span style={{ fontSize: 13, color: "#6b7280" }}>
          {chain?.name || `Chain ${chainId}`}
        </span>
        <span style={{ fontSize: 14, fontWeight: 600 }}>
          {shortAddr(address!)}
        </span>
        <button onClick={() => disconnect()} style={btnStyle("#ef4444")}>
          Disconnect
        </button>
      </div>
    );
  }
  return (
    <div style={{ display: "flex", gap: 8 }}>
      {connectors.map((c) => (
        <button
          key={c.id}
          onClick={() => connect({ connector: c })}
          style={btnStyle("#6366f1")}
        >
          {c.name}
        </button>
      ))}
    </div>
  );
}

function DashboardPanel() {
  const { address } = useAccount();
  const gov = useGovTokenData();
  const pool = usePoolData();
  const lending = useLendingPosition();
  const vault = useVaultData();
  const chainId = useChainId();
  const d = getDeployment(chainId);
  const { delegate, pending: govPending, error: govError } = useGovernanceTx();
  const [delErr, setDelErr] = useState<string | null>(null);

  const hf = lending.healthFactor;
  const hfDisplay = hf ? Number(formatUnits(hf, 18)).toFixed(3) : "—";
  const hfColor = hf && hf < 11n * 10n ** 17n ? "#ef4444" : "#10b981";

  async function selfDelegate() {
    if (!address) return;
    const hash = await delegate(address);
    if (!hash) setDelErr(govError);
  }

  return (
    <div
      style={{
        display: "grid",
        gridTemplateColumns: "repeat(auto-fit,minmax(260px,1fr))",
        gap: 16,
      }}
    >
      {/* Governance card */}
      <Card title="🗳️ Governance Token">
        <Row label="Balance" value={`${fmt(gov.balance)} DSAT`} />
        <Row label="Voting Power" value={`${fmt(gov.votes)} DSAT`} />
        <Row
          label="Delegate"
          value={gov.delegate ? shortAddr(gov.delegate) : "—"}
        />
        <Row
          label="Total Supply"
          value={`${fmt(gov.totalSupply)} / ${fmt(gov.maxSupply)}`}
        />
        {delErr && (
          <div style={{ color: "#ef4444", fontSize: 12 }}>{delErr}</div>
        )}
        <button
          onClick={selfDelegate}
          style={btnStyle("#6366f1")}
          disabled={govPending}
        >
          {govPending ? "Delegating…" : "Self-Delegate"}
        </button>
      </Card>

      {/* AMM pool card */}
      <Card title="💧 AMM Pool">
        {pool.paused && (
          <div style={{ color: "#ef4444", fontWeight: 700 }}>
            ⛔ Pool paused
          </div>
        )}
        <Row label="Reserve A" value={fmt(pool.reserveA)} />
        <Row label="Reserve B" value={fmt(pool.reserveB)} />
        {pool.reserveA &&
          pool.reserveB &&
          pool.reserveA > 0n &&
          pool.reserveB > 0n && (
            <Row
              label="Price A/B"
              value={(
                Number(formatUnits(pool.reserveB, 18)) /
                Number(formatUnits(pool.reserveA, 18))
              ).toFixed(6)}
            />
          )}
      </Card>

      {/* Lending position card */}
      <Card title="🏦 Lending Position">
        <Row label="Collateral" value={`${fmt(lending.collateral)} TKA`} />
        <Row label="Debt" value={`${fmt(lending.currentDebt)} TKB`} />
        <Row
          label="Health Factor"
          value={
            <span style={{ color: hfColor, fontWeight: 700 }}>{hfDisplay}</span>
          }
        />
        <Row
          label="Utilization"
          value={`${fmt(lending.utilizationRate, 16, 2)}%`}
        />
        <Row label="Total Protocol Debt" value={fmt(lending.totalDebt)} />
      </Card>

      {/* Vault card */}
      <Card title="📈 Yield Vault">
        <Row label="Total Assets" value={`${fmt(vault.totalAssets)} TKB`} />
        <Row label="Your Shares" value={fmt(vault.shares)} />
        <Row label="Share Price" value={`${fmt(vault.sharePrice)} TKB`} />
        <Row label="Total Shares" value={fmt(vault.totalSupply)} />
      </Card>
    </div>
  );
}

function SwapPanel() {
  const { address } = useAccount();
  const pool = usePoolData();
  const { swap, pending, error } = useSwap();
  const [amtIn, setAmtIn] = useState("");
  const [aToB, setAToB] = useState(true);
  const [slippage, setSlippage] = useState("0.5");
  const [txHash, setTxHash] = useState<string | null>(null);
  const [localErr, setLocalErr] = useState<string | null>(null);

  const rIn = aToB ? pool.reserveB : pool.reserveA;
  const rOut = aToB ? pool.reserveA : pool.reserveB;

  let amtOut = "";
  try {
    if (amtIn && rIn && rOut && rIn > 0n) {
      const inWei = parseUnits(amtIn, 18);
      const num = inWei * 997n * rOut;
      const den = rIn * 1000n + inWei * 997n;
      amtOut = formatUnits(num / den, 18);
    }
  } catch {}

  const minOut = amtOut
    ? (Number(amtOut) * (1 - Number(slippage) / 100)).toFixed(6)
    : "0";

  async function handleSwap() {
    setLocalErr(null);
    if (!address) {
      setLocalErr("Connect wallet first.");
      return;
    }
    if (!amtIn || Number(amtIn) <= 0) {
      setLocalErr("Enter a valid amount.");
      return;
    }
    const hash = await swap(amtIn, minOut, aToB, address);
    if (hash) {
      setTxHash(hash);
      setAmtIn("");
    } else if (error) setLocalErr(error);
  }

  return (
    <Card title="🔄 Swap">
      {localErr && (
        <ErrorBanner msg={localErr} onClose={() => setLocalErr(null)} />
      )}
      {txHash && (
        <div style={{ color: "#10b981", fontSize: 13, margin: "4px 0" }}>
          ✅ Tx: {shortAddr(txHash)}
        </div>
      )}
      <div style={{ display: "flex", gap: 8, marginBottom: 8 }}>
        <button
          onClick={() => setAToB(true)}
          style={btnStyle(
            aToB ? "#6366f1" : "#e5e7eb",
            aToB ? "#fff" : "#374151",
          )}
        >
          TKA → TKB
        </button>
        <button
          onClick={() => setAToB(false)}
          style={btnStyle(
            !aToB ? "#6366f1" : "#e5e7eb",
            !aToB ? "#fff" : "#374151",
          )}
        >
          TKB → TKA
        </button>
      </div>
      <label style={labelStyle}>Amount In</label>
      <input
        style={inputStyle}
        type="number"
        placeholder="0.0"
        value={amtIn}
        onChange={(e) => setAmtIn(e.target.value)}
      />
      <Row
        label="Estimated Out"
        value={amtOut ? Number(amtOut).toFixed(6) : "—"}
      />
      <label style={labelStyle}>Slippage %</label>
      <input
        style={{ ...inputStyle, width: 80 }}
        type="number"
        value={slippage}
        onChange={(e) => setSlippage(e.target.value)}
      />
      <button
        onClick={handleSwap}
        disabled={pending}
        style={{ ...btnStyle("#10b981"), marginTop: 8, width: "100%" }}
      >
        {pending ? "Swapping…" : "Swap"}
      </button>
    </Card>
  );
}


function AddLiquidityPanel() {
  const chainId = useChainId();
  const d = getDeployment(chainId);
  const pool = usePoolData();
  const { addLiquidity, pending, error } = useAddLiquidity();
  const tokenABalance = useTokenBalance(d?.tokenA);
  const tokenBBalance = useTokenBalance(d?.tokenB);
  const [amtA, setAmtA] = useState("");
  const [amtB, setAmtB] = useState("");
  const [txHash, setTxHash] = useState<string | null>(null);
  const [localErr, setLocalErr] = useState<string | null>(null);

  async function handleAddLiquidity() {
    setLocalErr(null);
    setTxHash(null);
    if (!amtA || Number(amtA) <= 0 || !amtB || Number(amtB) <= 0) {
      setLocalErr("Enter both token amounts.");
      return;
    }

    const hash = await addLiquidity(amtA, amtB);
    if (hash) {
      setTxHash(hash);
      setAmtA("");
      setAmtB("");
      pool.refetch();
      tokenABalance.refetch();
      tokenBBalance.refetch();
    } else if (error) {
      setLocalErr(error);
    }
  }

  return (
    <Card title="Add Liquidity">
      {localErr && (
        <ErrorBanner msg={localErr} onClose={() => setLocalErr(null)} />
      )}
      {txHash && (
        <div style={{ color: "#10b981", fontSize: 13, margin: "4px 0" }}>
          Tx: {shortAddr(txHash)}
        </div>
      )}

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit,minmax(220px,1fr))",
          gap: 12,
        }}
      >
        <div>
          <label style={labelStyle}>TKA Amount</label>
          <input
            style={inputStyle}
            type="number"
            placeholder="0.0"
            value={amtA}
            onChange={(e) => setAmtA(e.target.value)}
          />
          <div style={{ color: "#6b7280", fontSize: 12, marginTop: 4 }}>
            Balance: {fmt(tokenABalance.data as bigint | undefined)} TKA
          </div>
        </div>
        <div>
          <label style={labelStyle}>TKB Amount</label>
          <input
            style={inputStyle}
            type="number"
            placeholder="0.0"
            value={amtB}
            onChange={(e) => setAmtB(e.target.value)}
          />
          <div style={{ color: "#6b7280", fontSize: 12, marginTop: 4 }}>
            Balance: {fmt(tokenBBalance.data as bigint | undefined)} TKB
          </div>
        </div>
      </div>

      <div style={{ marginTop: 12 }}>
        <Row label="Current Reserve TKA" value={`${fmt(pool.reserveB)} TKA`} />
        <Row label="Current Reserve TKB" value={`${fmt(pool.reserveA)} TKB`} />
      </div>

      <button
        onClick={handleAddLiquidity}
        disabled={pending}
        style={{ ...btnStyle("#6366f1"), marginTop: 12, width: "100%" }}
      >
        {pending ? "Adding liquidity..." : "Add Liquidity"}
      </button>
    </Card>
  );
}

function LendingPanel() {
  const { depositCollateral, borrow, repay, supplyDebtToken, pending, error } =
    useLendingTx();
  const lending = useLendingPosition();
  const chainId = useChainId();
  const d = getDeployment(chainId);
  const debtTokenBalance = useTokenBalance(d?.tokenB);
  const [colAmt, setColAmt] = useState("");
  const [supplyAmt, setSupplyAmt] = useState("");
  const [borAmt, setBorAmt] = useState("");
  const [repAmt, setRepAmt] = useState("");
  const [localErr, setLocalErr] = useState<string | null>(null);
  const [txHash, setTxHash] = useState<string | null>(null);

  async function doDeposit() {
    setLocalErr(null);
    if (!colAmt || Number(colAmt) <= 0)
      return setLocalErr("Enter collateral amount.");
    const h = await depositCollateral(colAmt);
    if (h) {
      setTxHash(h);
      setColAmt("");
      lending.refetch();
    } else if (error) setLocalErr(error);
  }
  async function doSupply() {
    setLocalErr(null);
    if (!supplyAmt || Number(supplyAmt) <= 0)
      return setLocalErr("Enter TKB liquidity amount.");
    const h = await supplyDebtToken(supplyAmt);
    if (h) {
      setTxHash(h);
      setSupplyAmt("");
      lending.refetch();
      debtTokenBalance.refetch();
    } else if (error) setLocalErr(error);
  }
  async function doBorrow() {
    setLocalErr(null);
    if (!borAmt || Number(borAmt) <= 0)
      return setLocalErr("Enter borrow amount.");
    const h = await borrow(borAmt);
    if (h) {
      setTxHash(h);
      setBorAmt("");
      lending.refetch();
    } else if (error) setLocalErr(error);
  }
  async function doRepay() {
    setLocalErr(null);
    if (!repAmt || Number(repAmt) <= 0)
      return setLocalErr("Enter repay amount.");
    const h = await repay(repAmt);
    if (h) {
      setTxHash(h);
      setRepAmt("");
      lending.refetch();
    } else if (error) setLocalErr(error);
  }

  return (
    <Card title="🏦 Lending Pool">
      {localErr && (
        <ErrorBanner msg={localErr} onClose={() => setLocalErr(null)} />
      )}
      {txHash && (
        <div style={{ color: "#10b981", fontSize: 13 }}>
          ✅ Tx: {shortAddr(txHash)}
        </div>
      )}

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit,minmax(220px,1fr))",
          gap: 12,
        }}
      >
        <div>
          <label style={labelStyle}>Deposit Collateral (TKA)</label>
          <input
            style={inputStyle}
            type="number"
            placeholder="0.0"
            value={colAmt}
            onChange={(e) => setColAmt(e.target.value)}
          />
          <button
            onClick={doDeposit}
            disabled={pending}
            style={{ ...btnStyle("#6366f1"), width: "100%", marginTop: 4 }}
          >
            {pending ? "…" : "Deposit"}
          </button>
        </div>
        <div>
          <label style={labelStyle}>Supply Pool Liquidity (TKB)</label>
          <input
            style={inputStyle}
            type="number"
            placeholder="0.0"
            value={supplyAmt}
            onChange={(e) => setSupplyAmt(e.target.value)}
          />
          <div style={{ color: "#6b7280", fontSize: 12, marginTop: 4 }}>
            Balance: {fmt(debtTokenBalance.data as bigint | undefined)} TKB
          </div>
          <button
            onClick={doSupply}
            disabled={pending}
            style={{ ...btnStyle("#0ea5e9"), width: "100%", marginTop: 4 }}
          >
            {pending ? "â€¦" : "Supply TKB"}
          </button>
        </div>
        <div>
          <label style={labelStyle}>Borrow (TKB)</label>
          <input
            style={inputStyle}
            type="number"
            placeholder="0.0"
            value={borAmt}
            onChange={(e) => setBorAmt(e.target.value)}
          />
          <button
            onClick={doBorrow}
            disabled={pending}
            style={{ ...btnStyle("#f59e0b"), width: "100%", marginTop: 4 }}
          >
            {pending ? "…" : "Borrow"}
          </button>
        </div>
        <div>
          <label style={labelStyle}>Repay (TKB)</label>
          <input
            style={inputStyle}
            type="number"
            placeholder="0.0"
            value={repAmt}
            onChange={(e) => setRepAmt(e.target.value)}
          />
          <button
            onClick={doRepay}
            disabled={pending}
            style={{ ...btnStyle("#10b981"), width: "100%", marginTop: 4 }}
          >
            {pending ? "…" : "Repay"}
          </button>
        </div>
      </div>
    </Card>
  );
}

function VaultPanel() {
  const { deposit, redeem, pending, error } = useVaultTx();
  const vault = useVaultData();
  const [depAmt, setDepAmt] = useState("");
  const [localErr, setLocalErr] = useState<string | null>(null);
  const [txHash, setTxHash] = useState<string | null>(null);

  async function doDeposit() {
    setLocalErr(null);
    if (!depAmt || Number(depAmt) <= 0)
      return setLocalErr("Enter deposit amount.");
    const h = await deposit(depAmt);
    if (h) {
      setTxHash(h);
      setDepAmt("");
      vault.refetch();
    } else if (error) setLocalErr(error);
  }
  async function doRedeem() {
    setLocalErr(null);
    if (!vault.shares || vault.shares === 0n)
      return setLocalErr("No shares to redeem.");
    const h = await redeem(vault.shares);
    if (h) {
      setTxHash(h);
      vault.refetch();
    } else if (error) setLocalErr(error);
  }

  return (
    <Card title="📈 Yield Vault">
      {localErr && (
        <ErrorBanner msg={localErr} onClose={() => setLocalErr(null)} />
      )}
      {txHash && (
        <div style={{ color: "#10b981", fontSize: 13 }}>
          ✅ Tx: {shortAddr(txHash)}
        </div>
      )}
      <label style={labelStyle}>Deposit TKB</label>
      <input
        style={inputStyle}
        type="number"
        placeholder="0.0"
        value={depAmt}
        onChange={(e) => setDepAmt(e.target.value)}
      />
      <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
        <button
          onClick={doDeposit}
          disabled={pending}
          style={{ ...btnStyle("#6366f1"), flex: 1 }}
        >
          {pending ? "…" : "Deposit"}
        </button>
        <button
          onClick={doRedeem}
          disabled={pending || !vault.shares || vault.shares === 0n}
          style={{ ...btnStyle("#10b981"), flex: 1 }}
        >
          {pending ? "…" : `Redeem ${fmt(vault.shares, 18, 4)} shares`}
        </button>
      </div>
    </Card>
  );
}

function GovernancePanel() {
  const { data, isLoading } = useProposals();
  const { castVote, delegate, pending, error } = useGovernanceTx();
  const { address } = useAccount();
  const gov = useGovTokenData();
  const [voteErr, setVoteErr] = useState<string | null>(null);
  const [votedTx, setVotedTx] = useState<string | null>(null);

  async function handleVote(proposalId: string, support: number) {
    setVoteErr(null);
    const h = await castVote(BigInt(proposalId), support);
    if (h) setVotedTx(h);
    else if (error) setVoteErr(error);
  }

  async function handleDelegate() {
    if (!address) return;
    await delegate(address);
  }

  return (
    <Card title="🗳️ Governance — Proposals">
      {/* Voting power / delegate */}
      <div
        style={{
          display: "flex",
          gap: 12,
          alignItems: "center",
          marginBottom: 12,
          padding: 12,
          background: "#f8fafc",
          borderRadius: 8,
        }}
      >
        <div>
          <span style={{ fontSize: 12, color: "#6b7280" }}>Voting Power</span>
          <div style={{ fontWeight: 700 }}>{fmt(gov.votes)} DSAT</div>
        </div>
        <div>
          <span style={{ fontSize: 12, color: "#6b7280" }}>Delegate</span>
          <div style={{ fontWeight: 700 }}>
            {gov.delegate ? shortAddr(gov.delegate) : "None"}
          </div>
        </div>
        <button
          onClick={handleDelegate}
          disabled={pending}
          style={btnStyle("#6366f1")}
        >
          {pending ? "…" : "Self-Delegate"}
        </button>
      </div>

      {voteErr && (
        <ErrorBanner msg={voteErr} onClose={() => setVoteErr(null)} />
      )}
      {votedTx && (
        <div style={{ color: "#10b981", fontSize: 13, marginBottom: 8 }}>
          ✅ Vote cast: {shortAddr(votedTx)}
        </div>
      )}

      {isLoading && (
        <p style={{ color: "#6b7280" }}>Loading proposals from subgraph…</p>
      )}

      {data?.proposals.map((p) => (
        <div
          key={p.id}
          style={{
            border: "1px solid #e5e7eb",
            borderRadius: 8,
            padding: 12,
            marginBottom: 8,
          }}
        >
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              marginBottom: 4,
            }}
          >
            <span style={{ fontWeight: 600, fontSize: 14 }}>
              #{p.id.slice(0, 8)}… {p.description.slice(0, 80)}
              {p.description.length > 80 ? "…" : ""}
            </span>
            <StateBadge state={p.state} />
          </div>
          <div
            style={{
              display: "flex",
              gap: 16,
              fontSize: 13,
              color: "#6b7280",
              marginBottom: 8,
            }}
          >
            <span>✅ For: {Number(p.forVotes).toFixed(2)}</span>
            <span>❌ Against: {Number(p.againstVotes).toFixed(2)}</span>
            <span>⚪ Abstain: {Number(p.abstainVotes).toFixed(2)}</span>
          </div>
          {p.state === "Active" && (
            <div style={{ display: "flex", gap: 8 }}>
              <button
                onClick={() => handleVote(p.id, 1)}
                disabled={pending}
                style={btnStyle("#10b981")}
              >
                Vote For
              </button>
              <button
                onClick={() => handleVote(p.id, 0)}
                disabled={pending}
                style={btnStyle("#ef4444")}
              >
                Vote Against
              </button>
              <button
                onClick={() => handleVote(p.id, 2)}
                disabled={pending}
                style={btnStyle("#6b7280")}
              >
                Abstain
              </button>
            </div>
          )}
        </div>
      ))}

      {data?.proposals.length === 0 && !isLoading && (
        <p style={{ color: "#6b7280", textAlign: "center" }}>
          No proposals yet.
        </p>
      )}
    </Card>
  );
}

function RecentSwapsPanel() {
  const { data, isLoading } = useRecentSwaps();
  return (
    <Card title="🔄 Recent Swaps (from Subgraph)">
      {isLoading && <p style={{ color: "#6b7280" }}>Loading…</p>}
      <div style={{ overflowX: "auto" }}>
        <table
          style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}
        >
          <thead>
            <tr style={{ borderBottom: "2px solid #e5e7eb" }}>
              {["Sender", "Direction", "Amount In", "Amount Out", "Time"].map(
                (h) => (
                  <th
                    key={h}
                    style={{
                      padding: "4px 8px",
                      textAlign: "left",
                      color: "#6b7280",
                    }}
                  >
                    {h}
                  </th>
                ),
              )}
            </tr>
          </thead>
          <tbody>
            {data?.swaps.slice(0, 15).map((s) => (
              <tr key={s.id} style={{ borderBottom: "1px solid #f3f4f6" }}>
                <td style={{ padding: "4px 8px" }}>{shortAddr(s.sender)}</td>
                <td style={{ padding: "4px 8px" }}>{s.aToB ? "A→B" : "B→A"}</td>
                <td style={{ padding: "4px 8px" }}>
                  {Number(s.amountIn).toFixed(4)}
                </td>
                <td style={{ padding: "4px 8px" }}>
                  {Number(s.amountOut).toFixed(4)}
                </td>
                <td style={{ padding: "4px 8px" }}>
                  {new Date(Number(s.timestamp) * 1000).toLocaleTimeString()}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {(!data || data.swaps.length === 0) && !isLoading && (
          <p style={{ color: "#6b7280", textAlign: "center" }}>
            No swaps indexed yet.
          </p>
        )}
      </div>
    </Card>
  );
}

function Card({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div
      style={{
        background: "#fff",
        border: "1px solid #e5e7eb",
        borderRadius: 12,
        padding: 20,
        boxShadow: "0 1px 3px rgba(0,0,0,.06)",
      }}
    >
      <h3
        style={{
          margin: "0 0 12px",
          fontSize: 16,
          fontWeight: 700,
          color: "#111827",
        }}
      >
        {title}
      </h3>
      {children}
    </div>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div
      style={{
        display: "flex",
        justifyContent: "space-between",
        padding: "4px 0",
        borderBottom: "1px solid #f9fafb",
        fontSize: 14,
      }}
    >
      <span style={{ color: "#6b7280" }}>{label}</span>
      <span style={{ fontWeight: 600, color: "#111827" }}>{value}</span>
    </div>
  );
}

function btnStyle(bg: string, color = "#fff"): React.CSSProperties {
  return {
    background: bg,
    color,
    border: "none",
    borderRadius: 8,
    padding: "8px 16px",
    cursor: "pointer",
    fontWeight: 600,
    fontSize: 14,
  };
}

const labelStyle: React.CSSProperties = {
  display: "block",
  fontSize: 12,
  color: "#6b7280",
  marginBottom: 4,
  marginTop: 8,
};
const inputStyle: React.CSSProperties = {
  width: "100%",
  border: "1px solid #e5e7eb",
  borderRadius: 8,
  padding: "8px 12px",
  fontSize: 14,
  boxSizing: "border-box",
};

const TABS = [
  "Dashboard",
  "Swap",
  "Lending",
  "Vault",
  "Governance",
  "Analytics",
] as const;
type Tab = (typeof TABS)[number];

function App() {
  const [tab, setTab] = useState<Tab>("Dashboard");
  const { isConnected } = useAccount();

  return (
    <div
      style={{
        fontFamily: "Inter,system-ui,sans-serif",
        minHeight: "100vh",
        background: "#f9fafb",
      }}
    >
      {/* Header */}
      <header
        style={{
          background: "#fff",
          borderBottom: "1px solid #e5e7eb",
          padding: "0 24px",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          height: 64,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
          <span style={{ fontWeight: 800, fontSize: 20, color: "#6366f1" }}>
            ⚡ DeFi Super-App
          </span>
          <nav style={{ display: "flex", gap: 4 }}>
            {TABS.map((t) => (
              <button
                key={t}
                onClick={() => setTab(t)}
                style={{
                  background: tab === t ? "#eef2ff" : "none",
                  color: tab === t ? "#6366f1" : "#6b7280",
                  border: "none",
                  borderRadius: 8,
                  padding: "6px 14px",
                  fontWeight: tab === t ? 700 : 500,
                  cursor: "pointer",
                  fontSize: 14,
                }}
              >
                {t}
              </button>
            ))}
          </nav>
        </div>
        <WalletBar />
      </header>

      {/* Body */}
      <main style={{ maxWidth: 1200, margin: "0 auto", padding: "24px 24px" }}>
        <NetworkBanner />

        {!isConnected && (
          <div
            style={{ textAlign: "center", padding: "80px 0", color: "#6b7280" }}
          >
            <div style={{ fontSize: 48, marginBottom: 16 }}>🔗</div>
            <h2 style={{ color: "#111827" }}>
              Connect your wallet to get started
            </h2>
            <p>DeFi Super-App — AMM · Lending · Vault · DAO</p>
          </div>
        )}

        {isConnected && (
          <>
            {tab === "Dashboard" && <DashboardPanel />}
            {tab === "Swap" && (
              <div style={{ display: "grid", gap: 16 }}>
                <AddLiquidityPanel />
                <SwapPanel />
              </div>
            )}
            {tab === "Lending" && <LendingPanel />}
            {tab === "Vault" && <VaultPanel />}
            {tab === "Governance" && <GovernancePanel />}
            {tab === "Analytics" && <AnalyticsPanel />}
          </>
        )}
      </main>
    </div>
  );
}

function AnalyticsPanel() {
  const { data, isLoading } = useProtocolStats();
  const recentSwaps = useRecentSwaps();

  return (
    <div style={{ display: "grid", gap: 16 }}>
      <RecentSwapsPanel />
      <Card title="📊 Protocol Daily Stats (Subgraph)">
        {isLoading && <p style={{ color: "#6b7280" }}>Loading…</p>}
        <div style={{ overflowX: "auto" }}>
          <table
            style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}
          >
            <thead>
              <tr style={{ borderBottom: "2px solid #e5e7eb" }}>
                {[
                  "Date",
                  "Vol A",
                  "Vol B",
                  "Swaps",
                  "Liquidations",
                  "Vault Deposits",
                  "Yield Harvested",
                ].map((h) => (
                  <th
                    key={h}
                    style={{
                      padding: "4px 8px",
                      textAlign: "left",
                      color: "#6b7280",
                    }}
                  >
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {data?.protocolDayDatas.map((d) => (
                <tr key={d.id} style={{ borderBottom: "1px solid #f3f4f6" }}>
                  <td style={{ padding: "4px 8px" }}>
                    {new Date(d.date * 86400 * 1000).toLocaleDateString()}
                  </td>
                  <td style={{ padding: "4px 8px" }}>
                    {Number(d.dailyVolumeA).toFixed(2)}
                  </td>
                  <td style={{ padding: "4px 8px" }}>
                    {Number(d.dailyVolumeB).toFixed(2)}
                  </td>
                  <td style={{ padding: "4px 8px" }}>{d.dailySwaps}</td>
                  <td style={{ padding: "4px 8px" }}>{d.dailyLiquidations}</td>
                  <td style={{ padding: "4px 8px" }}>
                    {Number(d.dailyVaultDeposits).toFixed(2)}
                  </td>
                  <td style={{ padding: "4px 8px" }}>
                    {Number(d.dailyYieldHarvested).toFixed(4)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {(!data || data.protocolDayDatas.length === 0) && !isLoading && (
            <p style={{ color: "#6b7280", textAlign: "center" }}>
              No data indexed yet.
            </p>
          )}
        </div>
      </Card>
    </div>
  );
}

export default function Root() {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <App />
      </QueryClientProvider>
    </WagmiProvider>
  );
}
