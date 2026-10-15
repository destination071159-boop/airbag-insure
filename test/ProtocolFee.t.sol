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

/// The protocol fee: a share of each premium, taken out of what the underwriter receives.
contract ProtocolFeeTest is Test {
  Aqua aqua;
  CoverApp cover;
  CoverNote note;
  MockERC20 usdg;
  MockOracle oracle;

  address underwriter = makeAddr("underwriter");
  address buyer = makeAddr("buyer");
  address treasury = makeAddr("treasury");

  uint256 constant RESERVE = 1_000_000e18;
  uint256 constant COVER = 100_000e18;
  uint256 constant PEG = 1e8;

  function setUp() public {
    aqua = new Aqua();
    cover = new CoverApp(IAqua(address(aqua)), address(this));
    note = new CoverNote(address(cover));
    cover.initialize(note, SolventBook(address(0)));
    usdg = new MockERC20("Global Dollar", "USDG");
    oracle = new MockOracle(8, PEG);
  }

  function _ship() internal returns (bytes32 hash) {
    CoverApp.Market memory m = CoverApp.Market({
      underwriter: underwriter,
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
      salt: bytes32(uint256(1))
    });
    vm.startPrank(underwriter);
    usdg.mint(underwriter, RESERVE);
    usdg.approve(address(aqua), type(uint256).max);
    address[] memory tokens = new address[](1);
    tokens[0] = address(usdg);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = RESERVE;
    hash = aqua.ship(address(cover), abi.encode(m), tokens, amounts);
    cover.registerMarket(m);
    vm.stopPrank();
  }

  function _buy(bytes32 hash) internal returns (uint256 policyId, uint256 premium) {
    premium = cover.quotePremiumFor(hash, COVER, 30 days);
    vm.startPrank(buyer);
    usdg.mint(buyer, premium);
    usdg.approve(address(cover), premium);
    policyId = cover.buyPolicy(hash, COVER, 30 days);
    vm.stopPrank();
  }

  function test_no_fee_by_default() public {
    bytes32 hash = _ship();
    (, uint256 premium) = _buy(hash);
    assertEq(cover.protocolFeeBps(), 0);
    assertEq(usdg.balanceOf(underwriter), RESERVE + premium, "underwriter gets the whole premium");
    assertEq(usdg.balanceOf(address(cover)), 0);
  }

  function test_fee_is_taken_out_of_the_premium() public {
    bytes32 hash = _ship();
    uint256 quoteBefore = cover.quotePremiumFor(hash, COVER, 30 days);
    cover.setProtocolFee(1000, treasury); // 10%
    assertEq(cover.quotePremiumFor(hash, COVER, 30 days), quoteBefore, "the buyer's price does not change");

    (uint256 policyId, uint256 premium) = _buy(hash);
    uint256 fee = premium / 10;

    assertEq(usdg.balanceOf(buyer), 0, "buyer paid exactly the quote");
    assertEq(usdg.balanceOf(treasury), fee, "protocol got 10%");
    assertEq(usdg.balanceOf(underwriter), RESERVE + premium - fee, "underwriter got the rest");
    assertEq(usdg.balanceOf(address(cover)), 0, "nothing is left in the contract");
    (uint256 backing,,) = cover.solvency(hash);
    assertEq(backing, RESERVE + premium - fee, "backing grows by what the underwriter received");
    (,,,,,, uint256 recorded,) = cover.policies(policyId);
    assertEq(recorded, premium, "the policy records what the buyer paid");
  }

  function test_payout_is_never_charged() public {
    bytes32 hash = _ship();
    cover.setProtocolFee(2000, treasury);
    (uint256 policyId,) = _buy(hash);
    uint256 treasuryAfterBuy = usdg.balanceOf(treasury);

    oracle.set(0.9e8);
    assertEq(cover.payout(policyId), COVER);
    assertEq(usdg.balanceOf(buyer), COVER, "the holder receives the full cover");
    assertEq(usdg.balanceOf(treasury), treasuryAfterBuy, "no fee on the payout");
  }

  function test_only_owner_and_capped() public {
    vm.prank(buyer);
    vm.expectRevert(CoverApp.NotOwner.selector);
    cover.setProtocolFee(100, treasury);

    vm.expectRevert(abi.encodeWithSelector(CoverApp.FeeTooHigh.selector, uint16(2001), uint16(2000)));
    cover.setProtocolFee(2001, treasury);

    vm.expectRevert(CoverApp.ZeroFeeRecipient.selector);
    cover.setProtocolFee(100, address(0));

    cover.setProtocolFee(2000, treasury); // the ceiling itself is allowed
    cover.setProtocolFee(0, address(0)); // and the fee can be switched off again
    assertEq(cover.protocolFeeBps(), 0);
  }

  function test_a_new_fee_does_not_touch_policies_already_sold() public {
    bytes32 hash = _ship();
    (, uint256 premium) = _buy(hash);
    cover.setProtocolFee(1000, treasury);
    assertEq(usdg.balanceOf(treasury), 0);
    assertEq(usdg.balanceOf(underwriter), RESERVE + premium);
  }

  function test_router_orders_pay_the_fee_and_refund_the_rest() public {
    bytes32 hash = _ship();
    CoverRouter router = new CoverRouter(cover);
    cover.setProtocolFee(500, treasury); // 5%

    CoverRouter.Leg[] memory legs = new CoverRouter.Leg[](1);
    legs[0] = CoverRouter.Leg({strategyHash: hash, coverNotional: COVER});
    (, uint256 quoted) = router.quoteRouteFor(legs, 30 days);

    vm.startPrank(buyer);
    usdg.mint(buyer, quoted * 2);
    usdg.approve(address(router), quoted * 2);
    (, uint256 spent) = router.buyRoute(legs, address(usdg), quoted * 2, 30 days, buyer, block.timestamp + 1);
    vm.stopPrank();

    assertEq(spent, quoted, "the route costs what was quoted");
    assertEq(usdg.balanceOf(buyer), quoted, "the unspent half came back");
    assertEq(usdg.balanceOf(treasury), quoted * 500 / 10_000);
  }

  function testFuzz_split_always_adds_up(uint16 feeBps, uint256 notional, uint32 duration) public {
    feeBps = uint16(bound(feeBps, 0, 2000));
    notional = bound(notional, 1e18, 700_000e18);
    duration = uint32(bound(duration, 1 hours, 365 days));
    bytes32 hash = _ship();
    cover.setProtocolFee(feeBps, treasury);

    uint256 premium = cover.quotePremiumFor(hash, notional, duration);
    vm.startPrank(buyer);
    usdg.mint(buyer, premium);
    usdg.approve(address(cover), premium);
    cover.buyPolicy(hash, notional, duration);
    vm.stopPrank();

    uint256 toTreasury = usdg.balanceOf(treasury);
    uint256 toUnderwriter = usdg.balanceOf(underwriter) - RESERVE;
    assertEq(toTreasury + toUnderwriter, premium, "every unit of premium is accounted for");
    assertLe(toTreasury, premium * 2000 / 10_000, "never above the ceiling");
    assertEq(usdg.balanceOf(address(cover)), 0);
  }
}
