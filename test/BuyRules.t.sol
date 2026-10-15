// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Aqua} from "@1inch/aqua/src/Aqua.sol";
import {IAqua} from "@1inch/aqua/src/interfaces/IAqua.sol";

import {CoverApp} from "../src/CoverApp.sol";
import {CoverNote} from "../src/CoverNote.sol";
import {CoverRouter} from "../src/CoverRouter.sol";
import {SolventBook} from "../src/SolventBook.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";

/// Buy rules: the underwriter bounds a policy's term and can delay the start of cover.
contract BuyRulesTest is Test {
  Aqua aqua;
  CoverApp cover;
  CoverNote note;
  MockERC20 usdg;
  MockOracle oracle;
  bytes32 hash;

  address underwriter = makeAddr("underwriter");
  address buyer = makeAddr("buyer");

  uint256 constant RESERVE = 1_000_000e18;
  uint256 constant COVER = 50_000e18;
  uint256 constant PEG = 1e8;

  function setUp() public {
    aqua = new Aqua();
    cover = new CoverApp(IAqua(address(aqua)), address(this));
    note = new CoverNote(address(cover));
    cover.initialize(note, SolventBook(address(0)));
    usdg = new MockERC20("Global Dollar", "USDG");
    oracle = new MockOracle(8, PEG);
    hash = _ship(underwriter, 1);
  }

  function _ship(address who, uint256 salt) internal returns (bytes32 h) {
    CoverApp.Market memory m = CoverApp.Market({
      underwriter: who,
      asset: address(usdg),
      oracle: address(oracle),
      pegPrice: PEG,
      depegBps: 300,
      maxUtilBps: 8000,
      oracleTimeout: 1 hours,
      startRateWad: 0.01e18,
      endRateWad: 0.1e18,
      convexityWad: 1e18,
      trigger: address(0),
      salt: bytes32(salt)
    });
    vm.startPrank(who);
    usdg.mint(who, RESERVE);
    usdg.approve(address(aqua), type(uint256).max);
    address[] memory tokens = new address[](1);
    tokens[0] = address(usdg);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = RESERVE;
    h = aqua.ship(address(cover), abi.encode(m), tokens, amounts);
    cover.registerMarket(m);
    vm.stopPrank();
  }

  function _buy(uint64 duration) internal returns (uint256 policyId) {
    uint256 premium = cover.quotePremiumFor(hash, COVER, duration);
    vm.startPrank(buyer);
    usdg.mint(buyer, premium);
    usdg.approve(address(cover), premium);
    policyId = cover.buyPolicy(hash, COVER, duration);
    vm.stopPrank();
  }

  function _limit(uint64 minDuration, uint64 maxDuration) internal {
    vm.prank(underwriter);
    cover.setBuyRules(hash, minDuration, maxDuration, 0);
  }

  function _expectOutOfRange(uint64 duration, uint64 minDuration, uint64 maxDuration) internal {
    vm.prank(buyer);
    vm.expectRevert(
      abi.encodeWithSelector(CoverApp.DurationOutOfRange.selector, duration, minDuration, maxDuration)
    );
    cover.buyPolicy(hash, COVER, duration);
  }

  function test_any_term_by_default() public {
    (uint64 minDuration, uint64 maxDuration, uint64 waitingPeriod) = cover.buyRules(hash);
    assertEq(minDuration + maxDuration + waitingPeriod, 0);
    _buy(5 minutes);
    _buy(5 * 365 days);
  }

  function test_term_is_bounded_both_ways() public {
    _limit(7 days, 90 days);
    _buy(7 days);
    _buy(90 days);
    _expectOutOfRange(1 hours, 7 days, 90 days);
    _expectOutOfRange(91 days, 7 days, 90 days);
  }

  function test_minimum_only() public {
    _limit(7 days, 0);
    _buy(5 * 365 days);
    _expectOutOfRange(6 days, 7 days, 0);
  }

  function test_maximum_only() public {
    _limit(0, 30 days);
    _buy(1);
    _expectOutOfRange(31 days, 0, 30 days);
  }

  function test_only_the_underwriter_sets_limits_and_they_must_make_sense() public {
    vm.prank(buyer);
    vm.expectRevert(CoverApp.NotUnderwriter.selector);
    cover.setBuyRules(hash, 7 days, 0, 0);

    vm.prank(underwriter);
    vm.expectRevert(CoverApp.BadBuyRules.selector);
    cover.setBuyRules(hash, 30 days, 7 days, 0);
  }

  function test_new_limits_do_not_touch_sold_policies() public {
    uint256 id = _buy(1 hours);
    _limit(7 days, 0);

    oracle.set(0.9e8);
    uint256 before = usdg.balanceOf(buyer);
    cover.payout(id);
    assertEq(usdg.balanceOf(buyer) - before, COVER, "a policy sold before the limit still pays in full");
  }

  function test_a_route_through_a_market_that_refuses_the_term_reverts_whole() public {
    bytes32 other = _ship(makeAddr("other"), 2);
    _limit(7 days, 0);
    CoverRouter router = new CoverRouter(cover);

    CoverRouter.Leg[] memory legs = new CoverRouter.Leg[](2);
    legs[0] = CoverRouter.Leg(other, COVER);
    legs[1] = CoverRouter.Leg(hash, COVER);
    uint256 max = 1_000e18;
    vm.startPrank(buyer);
    usdg.mint(buyer, max);
    usdg.approve(address(router), max);
    vm.expectRevert(abi.encodeWithSelector(CoverApp.DurationOutOfRange.selector, 1 days, 7 days, 0));
    router.buyRoute(legs, address(usdg), max, 1 days, buyer, block.timestamp + 1);
    vm.stopPrank();
    assertEq(cover.outstanding(other), 0, "nothing was bought on the other leg either");
  }
}
