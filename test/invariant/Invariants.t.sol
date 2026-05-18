// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../unit/BaseTest.t.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Handler — drives random calls into the AMM
// ─────────────────────────────────────────────────────────────────────────────
contract AMMHandler is BaseTest {
    uint256 public ghost_totalLPMinted;
    uint256 public ghost_totalLPBurned;

    function setUp() public override {
        super.setUp();
        // initial liquidity so k starts non-zero
        _addLiquidity(alice, 1000e18, 2000e18);
        ghost_totalLPMinted = amm.lpToken().totalSupply();
    }

    function addLiq(uint256 amtA, uint256 amtB) external {
        amtA = bound(amtA, 1, 500e18);
        amtB = bound(amtB, 1, 1000e18);
        tokenA.mint(address(this), amtA);
        tokenB.mint(address(this), amtB);
        tokenA.approve(address(amm), amtA);
        tokenB.approve(address(amm), amtB);
        (,, uint256 lp) = amm.addLiquidity(amtA, amtB, 0, 0);
        ghost_totalLPMinted += lp;
    }

    function removeLiq(uint256 pct) external {
        uint256 bal = amm.lpToken().balanceOf(address(this));
        if (bal == 0) return;
        pct = bound(pct, 1, 100);
        uint256 toRemove = bal * pct / 100;
        amm.lpToken().approve(address(amm), toRemove);
        amm.removeLiquidity(toRemove, 0, 0);
        ghost_totalLPBurned += toRemove;
    }

    function doSwap(uint256 amtIn, bool aToB) external {
        (uint112 rA, uint112 rB,) = amm.getReserves();
        if (rA == 0 || rB == 0) return;
        uint256 cap = aToB ? uint256(rA) / 10 : uint256(rB) / 10;
        amtIn = bound(amtIn, 1, cap == 0 ? 1 : cap);

        if (aToB) {
            tokenA.mint(address(this), amtIn);
            tokenA.approve(address(amm), amtIn);
        } else {
            tokenB.mint(address(this), amtIn);
            tokenB.approve(address(amm), amtIn);
        }
        amm.swap(amtIn, 0, aToB, address(this));
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant: k never decreases
// ─────────────────────────────────────────────────────────────────────────────
contract Invariant_AMM_KNeverDecreases is AMMHandler {
    uint256 private _kSnapshot;

    function setUp() public override {
        super.setUp();
        (uint112 rA, uint112 rB,) = amm.getReserves();
        _kSnapshot = uint256(rA) * uint256(rB);
        targetContract(address(this));
    }

    /// @notice After every action, k ≥ initial k.
    function invariant_k_neverDecreases() public view {
        (uint112 rA, uint112 rB,) = amm.getReserves();
        uint256 kNow = uint256(rA) * uint256(rB);
        assertGe(kNow, _kSnapshot);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant: LP total supply = minted - burned
// ─────────────────────────────────────────────────────────────────────────────
contract Invariant_LP_TotalSupply is AMMHandler {
    function setUp() public override {
        super.setUp();
        targetContract(address(this));
    }

    function invariant_lpTotalSupply_conservation() public view {
        uint256 locked = amm.MINIMUM_LIQUIDITY(); // locked at address(1)
        uint256 supply = amm.lpToken().totalSupply();
        // supply = ghost_totalLPMinted + locked - ghost_totalLPBurned
        assertEq(supply, ghost_totalLPMinted + locked - ghost_totalLPBurned);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant: vault totalAssets ≥ sum of all depositors' claims
// ─────────────────────────────────────────────────────────────────────────────
contract Invariant_Vault_Solvency is BaseTest {
    address[] private depositors;
    uint256 private totalDeposited;

    function setUp() public override {
        super.setUp();
        depositors.push(alice);
        depositors.push(bob);
        depositors.push(carol);
        targetContract(address(this));
    }

    function depositToVault(uint256 assets, uint8 who) external {
        address user = depositors[who % depositors.length];
        assets = bound(assets, 1e6, 5000e18);
        tokenB.mint(user, assets);
        vm.startPrank(user);
        tokenB.approve(address(vault), assets);
        vault.deposit(assets, user);
        vm.stopPrank();
        totalDeposited += assets;
    }

    function invariant_vault_totalAssets_covers_claims() public view {
        uint256 totalClaims = 0;
        for (uint256 i = 0; i < depositors.length; i++) {
            uint256 shares = vault.balanceOf(depositors[i]);
            totalClaims += vault.convertToAssets(shares);
        }
        assertGe(vault.totalAssets(), totalClaims);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant: governance token supply ≤ maxSupply
// ─────────────────────────────────────────────────────────────────────────────
contract Invariant_GovToken_SupplyCap is BaseTest {
    function setUp() public override {
        super.setUp();
        targetContract(address(this));
    }

    function mintTokens(uint256 amount) external {
        uint256 cap = govToken.maxSupply() - govToken.totalSupply();
        if (cap == 0) return;
        amount = bound(amount, 1, cap);
        vm.prank(admin);
        govToken.mint(admin, amount);
    }

    function invariant_totalSupply_belowCap() public view {
        assertLe(govToken.totalSupply(), govToken.maxSupply());
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant: lending totalDebt ≥ sum of individual debts
// ─────────────────────────────────────────────────────────────────────────────
contract Invariant_Lending_DebtAccounting is BaseTest {
    address[] private borrowers;

    function setUp() public override {
        super.setUp();
        borrowers.push(alice);
        borrowers.push(bob);
        borrowers.push(carol);

        // Supply debt token liquidity
        _supplyDebt(alice, 20_000e18);

        targetContract(address(this));
    }

    function depositAndBorrow(uint256 colAmt, uint256 borrowAmt, uint8 who) external {
        address user = borrowers[who % borrowers.length];
        colAmt = bound(colAmt, 1e17, 5e18);
        borrowAmt = bound(borrowAmt, 1, 100e18);

        tokenA.mint(user, colAmt);
        vm.startPrank(user);
        tokenA.approve(address(lending), colAmt);
        lending.depositCollateral(colAmt);
        // attempt borrow, may revert on LTV — that's fine
        try lending.borrow(borrowAmt) {} catch {}
        vm.stopPrank();
    }

    function invariant_totalDebt_geq_sumOfDebts() public view {
        uint256 sumDebts = 0;
        for (uint256 i = 0; i < borrowers.length; i++) {
            (, uint256 debt,,) = lending.positions(borrowers[i]);
            sumDebts += debt;
        }
        assertGe(lending.totalDebt(), sumDebts);
    }
}
