// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Aqua} from "@1inch/aqua/src/Aqua.sol";
import {IAqua} from "@1inch/aqua/src/interfaces/IAqua.sol";

import {CoverApp} from "../src/CoverApp.sol";
import {CoverNote} from "../src/CoverNote.sol";
import {SolventBook} from "../src/SolventBook.sol";
import {PriceGapTrigger} from "../src/triggers/PriceGapTrigger.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";

/// The settlement fixes: no cover for an event already under way, a waiting period, proportional
/// payouts that top up instead of closing early, and events recorded by `poke` so that a dip
/// that recovers, or an event just before expiry, is still paid.
contract SettlementTest is Test {
  Aqua aqua;
  CoverApp cover;
  CoverNote note;
  MockERC20 usdg;
  MockOracle usdgFeed;
  MockOracle stockFeed;
  PriceGapTrigger gap;
  bytes32 depeg; // built-in depeg at $0.97, pays 100%
  bytes32 stock; // gap-down below a $250 strike, pays the fall in proportion

  address underwriter = makeAddr("underwriter");
  address buyer = makeAddr("buyer");
  address keeper = makeAddr("keeper");

  uint256 constant RESERVE = 1_000_000e18;
  uint256 constant COVER = 10_000e18;
  uint256 constant PEG = 1e8;
  uint256 constant STRIKE = 250e8;

  function setUp() public {
    vm.warp(1_000_000);
    aqua = new Aqua();
    cover = new CoverApp(IAqua(address(aqua)), address(this));
    note = new CoverNote(address(cover));
    cover.initialize(note, SolventBook(address(0)));
    usdg = new MockERC20("Global Dollar", "USDG");
    usdgFeed = new MockOracle(8, PEG);
    stockFeed = new MockOracle(8, STRIKE);
    gap = new PriceGapTrigger();

    vm.startPrank(underwriter);
    usdg.mint(underwriter, 2 * RESERVE);
    usdg.approve(address(aqua), type(uint256).max);
    vm.stopPrank();
    depeg = _ship(address(usdgFeed), address(0), 1);
    stock = _ship(address(stockFeed), address(gap), 2);
    gap.configure(stock, address(stockFeed), STRIKE, 1 hours);
  }

  function _ship(address oracle, address trigger, uint256 salt) internal returns (bytes32 h) {
    CoverApp.Market memory m = CoverApp.Market({
      underwriter: underwriter,
      asset: address(usdg),
      oracle: oracle,
      pegPrice: PEG,
      depegBps: 300,
      maxUtilBps: 8000,
      oracleTimeout: 1 hours,
      startRateWad: 0.01e18,
      endRateWad: 0.1e18,
      convexityWad: 1e18,
      trigger: trigger,
      salt: bytes32(salt)
    });
    address[] memory tokens = new address[](1);
    tokens[0] = address(usdg);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = RESERVE;
    vm.startPrank(underwriter);
    h = aqua.ship(address(cover), abi.encode(m), tokens, amounts);
    cover.registerMarket(m);
    vm.stopPrank();
  }

  function _buy(bytes32 h, uint64 duration) internal returns (uint256 id) {
    uint256 premium = cover.quotePremiumFor(h, COVER, duration);
    vm.startPrank(buyer);
    usdg.mint(buyer, premium);
    usdg.approve(address(cover), premium);
    id = cover.buyPolicy(h, COVER, duration);
    vm.stopPrank();
  }

  function _paid() internal view returns (uint256) {
    return usdg.balanceOf(buyer);
  }

  // ── 1. no cover for an event already under way ─────────────────────────

  function test_cannot_buy_depeg_cover_during_a_depeg() public {
    usdgFeed.set(0.95e8);
    vm.expectRevert(CoverApp.EventInProgress.selector);
    cover.buyPolicy(depeg, COVER, 7 days);
  }

  function test_cannot_buy_gap_cover_below_the_strike() public {
    stockFeed.set(240e8);
    vm.expectRevert(CoverApp.EventInProgress.selector);
    cover.buyPolicy(stock, COVER, 7 days);
  }

  function test_a_recorded_event_blocks_buying_until_it_is_seen_to_end() public {
    usdgFeed.set(0.95e8);
    cover.poke(depeg);
    usdgFeed.set(PEG); // recovered, but nobody has recorded that yet
    vm.expectRevert(CoverApp.EventInProgress.selector);
    cover.buyPolicy(depeg, COVER, 7 days);

    cover.poke(depeg); // anyone records the recovery
    _buy(depeg, 7 days);
  }

  // ── 2. waiting period ──────────────────────────────────────────────────

  function test_waiting_period_delays_cover_and_extends_the_term() public {
    vm.prank(underwriter);
    cover.setBuyRules(depeg, 0, 0, 1 days);
    uint256 id = _buy(depeg, 7 days);
    (,, uint64 expiry,,,,,) = cover.policies(id);
    assertEq(cover.startOf(id), block.timestamp + 1 days);
    assertEq(expiry, block.timestamp + 8 days, "the buyer still gets the full 7 days of cover");

    usdgFeed.set(0.9e8);
    vm.expectRevert(abi.encodeWithSelector(CoverApp.CoverNotStarted.selector, uint64(block.timestamp + 1 days)));
    cover.payout(id);
  }

  function test_an_event_that_began_in_the_waiting_period_is_not_covered() public {
    vm.prank(underwriter);
    cover.setBuyRules(depeg, 0, 0, 1 days);
    uint256 id = _buy(depeg, 7 days);

    vm.warp(block.timestamp + 12 hours);
    usdgFeed.set(0.9e8);
    cover.poke(depeg); // the depeg starts during the waiting period

    vm.warp(block.timestamp + 13 hours); // cover has started, the depeg goes on
    usdgFeed.set(0.9e8);
    cover.poke(depeg);
    vm.expectRevert(CoverApp.NothingMoreDue.selector);
    cover.payout(id);
  }

  function test_an_event_after_the_waiting_period_pays() public {
    vm.prank(underwriter);
    cover.setBuyRules(depeg, 0, 0, 1 days);
    uint256 id = _buy(depeg, 7 days);
    vm.warp(block.timestamp + 2 days);
    usdgFeed.set(0.9e8);
    cover.payout(id);
    assertEq(_paid(), COVER);
  }

  // ── 3. proportional payouts top up ─────────────────────────────────────

  function test_an_early_partial_payout_is_topped_up_when_the_loss_deepens() public {
    uint256 id = _buy(stock, 30 days);

    stockFeed.set(225e8); // -10%
    vm.prank(underwriter); // even the underwriter firing early cannot close the policy
    cover.payout(id);
    assertEq(_paid(), COVER / 10);
    assertEq(note.holderOf(id), buyer, "the policy is still open");
    assertEq(cover.outstanding(stock), COVER - COVER / 10, "only what may still be paid stays reserved");

    vm.expectRevert(CoverApp.NothingMoreDue.selector);
    cover.payout(id); // nothing new at the same depth

    vm.warp(block.timestamp + 1 days);
    stockFeed.set(150e8); // -40%
    vm.prank(keeper);
    cover.payout(id);
    assertEq(_paid(), COVER * 4 / 10, "paid the difference, 40% in total");

    vm.warp(block.timestamp + 30 days);
    cover.expire(id);
    assertEq(cover.outstanding(stock), 0, "the unpaid rest is released at expiry");
  }

  function test_a_full_payout_closes_the_policy_at_once() public {
    uint256 id = _buy(depeg, 30 days);
    usdgFeed.set(0.9e8);
    cover.payout(id);
    assertEq(_paid(), COVER);
    assertEq(note.holderOf(id), address(0), "note burned");
    assertEq(cover.outstanding(depeg), 0);
  }

  // ── 4. recorded events ─────────────────────────────────────────────────

  function test_a_dip_that_recovered_is_still_paid_if_it_was_recorded() public {
    uint256 id = _buy(depeg, 7 days);
    vm.warp(block.timestamp + 1 days);
    usdgFeed.set(0.92e8);
    vm.prank(keeper);
    cover.poke(depeg);

    vm.warp(block.timestamp + 10 minutes);
    usdgFeed.set(PEG);
    cover.poke(depeg); // the episode closes

    cover.payout(id);
    assertEq(_paid(), COVER, "paid for the dip after the price came back");
  }

  function test_an_unrecorded_dip_that_recovered_pays_nothing() public {
    uint256 id = _buy(depeg, 7 days);
    usdgFeed.set(0.92e8);
    usdgFeed.set(PEG); // nobody poked or fired in between
    vm.expectRevert(abi.encodeWithSelector(CoverApp.NotDepegged.selector, PEG, 0.97e8));
    cover.payout(id);
  }

  function test_an_event_just_before_expiry_can_be_paid_in_the_grace_period() public {
    uint256 id = _buy(depeg, 7 days);
    vm.warp(block.timestamp + 7 days - 1 hours);
    usdgFeed.set(0.9e8);
    cover.poke(depeg); // the keeper records it, then goes down

    vm.warp(block.timestamp + 2 days); // policy expired a day ago
    vm.expectRevert(CoverApp.PolicyNotExpired.selector);
    cover.expire(id); // capacity is held for the grace period

    cover.payout(id);
    assertEq(_paid(), COVER);
  }

  function test_after_the_grace_period_it_is_too_late() public {
    uint256 id = _buy(depeg, 7 days);
    vm.warp(block.timestamp + 7 days - 1 hours);
    usdgFeed.set(0.9e8);
    cover.poke(depeg);

    vm.warp(block.timestamp + 1 hours + cover.CLAIM_GRACE() + 1);
    vm.expectRevert(CoverApp.PolicyExpired.selector);
    cover.payout(id);
    cover.expire(id);
    assertEq(cover.outstanding(depeg), 0);
  }

  function test_an_event_after_expiry_is_not_covered() public {
    uint256 id = _buy(depeg, 7 days);
    vm.warp(block.timestamp + 7 days + 1);
    usdgFeed.set(0.9e8);
    cover.poke(depeg);
    vm.expectRevert(CoverApp.PolicyExpired.selector);
    cover.payout(id);
    cover.expire(id); // nothing recorded in its term, so it can be expired at once
  }

  function test_poke_refuses_a_stale_price() public {
    vm.warp(block.timestamp + 2 hours);
    vm.expectRevert(CoverApp.StaleOracle.selector);
    cover.poke(depeg);
  }
}
