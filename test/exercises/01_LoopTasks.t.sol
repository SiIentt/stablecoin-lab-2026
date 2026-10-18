// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";

/// @title Ex2 + Ex4 — hands-on tasks: turn red into green
/// @notice Every `assertTrue(false, "TODO ...")` below is a placeholder. Write the real
///         assertion, watch the test go green, and that exercise is done.
///
///         Acceptance: make exercise (it should be red until you are finished)
///         Do not open test/Stablecoin.t.sol — it contains the answers. Write yours
///         first, and only look once you are stuck.
contract LoopTasksTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));
    }

    // ==================================================================
    // Ex2 · the decimals trap: a 6-decimal stablecoin meets 18-decimal intuition
    // ==================================================================

    /// @dev For any legitimate amount x, totalSupply() must grow by exactly x after
    ///      deposit(x). Hint: use vm.assume to rule out x == 0, and faucet alice enough
    ///      usdc first.
    function test_Ex2_DepositIncreasesSupplyByExactly(uint96 raw) public {
        uint256 amount = uint256(raw) % 1_000_000e6;
        // assertTrue(false, "TODO Ex2.1");
        vm.assume(amount > 0);

        // give Alice enough collateral
        usdc.faucet(alice, amount);

        uint256 supplyBefore = stable.totalSupply();
        uint256 collateralBefore = vault.totalCollateral();
        uint256 balanceBefore = stable.balanceOf(alice);

        // simulate Alice approving and depositing collateral
        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        // check the increases in supply, collateral, and user balance
        assertEq(stable.totalSupply(), supplyBefore + amount);
        assertEq(vault.totalCollateral(), collateralBefore + amount);
        assertEq(stable.balanceOf(alice), balanceBefore + amount);
    }

    /// @dev Run deposit with 1000e18 instead of 1000e6, see what happens, then assert what
    ///      you observed. MockUSDC has 6 decimals — 1000e18 is one billion USDC.
    ///      There is no expected answer here; the point is that you run it yourself and
    ///      read the numbers.
    function test_Ex2_DecimalsTrap() public {
        // assertTrue(false, "TODO Ex2.2");
        uint256 intendedAmount = 1000e6;
        uint256 wrongAmount = 1000e18;

        // the test faucet can mint this extremely large amount
        usdc.faucet(alice, wrongAmount);

        vm.startPrank(alice);
        usdc.approve(address(vault), wrongAmount);
        vault.deposit(wrongAmount);
        vm.stopPrank();

        assertEq(usdc.decimals(), 6);
        assertEq(stable.decimals(), 6);

        // the deposit succeeds, and collateral still equals supply
        assertEq(stable.totalSupply(), wrongAmount);
        assertEq(vault.totalCollateral(), stable.totalSupply());
        assertEq(stable.balanceOf(alice), wrongAmount);

        // however, the amount is 10^12 times larger than intended
        assertEq(wrongAmount / intendedAmount, 1e12);
        assertEq(wrongAmount / 1e6, 1e15);

        emit log_named_uint("Intended raw amount", intendedAmount);
        emit log_named_uint("Actual raw amount", wrongAmount);
        emit log_named_uint("Actual whole tokens", wrongAmount / 1e6);    
    }

    // ==================================================================
    // Ex4 · permissions and pausing: where the guard is, who holds the key
    // ==================================================================

    /// @dev The attacker has no MINTER_ROLE, so calling mint directly must revert. Use
    ///      vm.expectRevert + abi.encodeWithSelector to pin down the exact error.
    function test_Ex4_Mint_RevertsForNonMinter() public {
        // assertTrue(false, "TODO Ex4.1");
        uint256 amount = 100e6;
        bytes32 minterRole = stable.MINTER_ROLE();

        // expect the exact access-control error for the attacker
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                attacker,
                minterRole
            )
        );

        // attempt to mint as an account without MINTER_ROLE
        vm.prank(attacker);
        stable.mint(attacker, amount);

        // the rejected call must not create any tokens
        assertEq(stable.totalSupply(), 0);
        assertEq(stable.balanceOf(attacker), 0);
    }

    /// @dev After pause(), an ordinary transfer must revert
    function test_Ex4_Pause_BlocksTransfers() public {
        // assertTrue(false, "TODO Ex4.2");
        uint256 amount = 100e6;

        // give Alice tokens before pausing the contract
        stable.mint(alice, amount);
        stable.pause();

        // transfers must revert while paused
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(alice);
        stable.transfer(attacker, amount);

        // the failed transfer must leave balances unchanged
        assertEq(stable.balanceOf(alice), amount);
        assertEq(stable.balanceOf(attacker), 0);
    }

    /// @dev What pause() freezes is _update, so redemption is frozen along with everything
    ///      else — why is that bad news in a real crisis?
    ///      (This is STUDENT-QUESTIONS.md B1 and B2.)
    function test_Ex4_Pause_BlocksRedeem() public {
        // assertTrue(false, "TODO Ex4.3");
        uint256 amount = 100e6;

        // complete a normal deposit before pausing
        usdc.faucet(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        stable.pause();

        // redemption burns stablecoins, which is also blocked by pause
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(alice);
        vault.redeem(amount);

        // the failed redemption must leave tokens and collateral unchanged
        assertEq(stable.balanceOf(alice), amount);
        assertEq(stable.totalSupply(), amount);
        assertEq(vault.totalCollateral(), amount);
        assertEq(usdc.balanceOf(alice), 0);
    }

    /// @dev An attacker cannot burn someone else's balance
    function test_Ex4_AttackerCannotBurnOthersBalance() public {
        // assertTrue(false, "TODO Ex4.4");
        uint256 amount = 100e6;
        bytes32 minterRole = stable.MINTER_ROLE();

        // give Alice a balance that the attacker will try to burn
        stable.mint(alice, amount);

        // burning requires MINTER_ROLE, which the attacker does not hold
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                attacker,
                minterRole
            )
        );

        vm.prank(attacker);
        stable.burn(alice, amount);

        // Alice's balance and the total supply must remain unchanged
        assertEq(stable.balanceOf(alice), amount);
        assertEq(stable.totalSupply(), amount);
    }

    /// @dev ...but the vault can, because it holds MINTER_ROLE and burn() answers to that
    ///      same role. This test proves the backdoor exists; it does not justify it.
    function test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance() public {
        // assertTrue(false, "TODO Ex4.5");
        uint256 amount = 100e6;

        // give Alice fully backed stablecoins through a normal deposit
        usdc.faucet(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        // verify that the vault holds the role required to burn tokens
        assertTrue(stable.hasRole(stable.MINTER_ROLE(), address(vault)));

        // simulate a call from the vault without Alice's authorization
        vm.prank(address(vault));
        stable.burn(alice, amount);

        // the vault's role permits burning Alice's entire balance
        assertEq(stable.balanceOf(alice), 0);
        assertEq(stable.totalSupply(), 0);

        // this direct burn does not return Alice's collateral
        assertEq(vault.totalCollateral(), amount);
        assertEq(usdc.balanceOf(alice), 0);
    }
}
