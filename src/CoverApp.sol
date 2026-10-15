// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAqua} from "@1inch/aqua/src/interfaces/IAqua.sol";
import {AquaApp} from "@1inch/aqua/src/AquaApp.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IReserveHook} from "./interfaces/IReserveHook.sol";
import {ITrigger} from "./interfaces/ITrigger.sol";
import {IPremiumPricer} from "./interfaces/IPremiumPricer.sol";
import {RiskCurve} from "./libraries/RiskCurve.sol";
import {CoverNote} from "./CoverNote.sol";
import {SolventBook} from "./SolventBook.sol";

/// @title Airbag CoverApp
/// @notice Non-custodial, provably-solvent, parametric depeg cover on 1inch Aqua.
///         - Underwriters `ship` USDG virtual balances (reserve stays in their wallet, can earn yield).
///         - Buyers pay a risk-curve premium (`push`ed to the underwriter) and receive an ERC-6909
///           CoverNote (transferable, so cover is assignable).
///         - On a depeg the covered notional is `pull`ed from the underwriter to the note holder,
///           atomically. Per-market and (optional) aggregate SolventBook floors prevent overselling.
///         - The protocol keeps an optional share of each premium (`protocolFeeBps`); payouts are
///           never charged.
contract CoverApp is AquaApp {
  using SafeERC20 for IERC20;

  struct Market {
    address underwriter; // Aqua maker
    address asset; // insured + reserve + settlement token (e.g. USDG)
    address oracle; // price feed for `asset`
    uint256 pegPrice; // target price in oracle decimals (e.g. 1e8 for $1)
    uint16 depegBps; // triggers when price <= peg * (1e4 - depegBps) / 1e4
    uint16 maxUtilBps; // outstanding cover <= backing * maxUtilBps / 1e4 (solvency floor)
    uint32 oracleTimeout; // max oracle staleness (seconds)
    uint256 startRateWad; // risk curve: premium rate at 0% utilization (WAD)
    uint256 endRateWad; // risk curve: premium rate at 100% utilization (WAD)
    uint256 convexityWad; // risk curve: shape (1e18 linear, >1e18 convex)
    address trigger; // address(0) = built-in depeg (oracle band); else an external ITrigger product
    bytes32 salt;
  }

  struct Policy {
    bytes32 marketHash;
    uint256 coverNotional;
    uint64 expiry;
    bool claimed;
    address buyer;
    uint64 boughtAt;
    uint256 premium;
    uint256 paidOut;
  }

  /// @notice Per-market purchase rules, set by the underwriter. 0 = none. Kept outside `Market` so
  ///         the strategy hash does not change.
  struct BuyRules {
    uint64 minDuration; // shortest term, in seconds: cover cannot be rented by the hour before an event
    uint64 maxDuration; // longest term, in seconds: today's price cannot be locked in for years
    uint64 waitingPeriod; // seconds between purchase and the start of cover; the term starts after it
  }

  /// @notice A stretch of time in which a market's trigger was seen true, recorded by `poke`.
  ///         It lets a policy be paid for an event that has since ended, or that came just before
  ///         expiry, without anyone having to fire the payout at that exact moment.
  struct Episode {
    uint64 start; // first time the trigger was seen true
    uint64 lastSeen; // last time it was seen true
    uint16 maxBps; // deepest payout fraction seen
  }

  uint256 internal constant BPS = 10_000;
  uint256 internal constant WAD = 1e18;
  /// @dev Risk-curve rates are ANNUAL: a policy pays rate(u) × notional × term / YEAR, like real cover.
  uint256 internal constant YEAR = 365 days;
  /// @notice How long after expiry a policy can still be paid for an event recorded during its term.
  uint64 public constant CLAIM_GRACE = 3 days;
  /// @notice Hard ceiling on the protocol's share of a premium (20%), so the owner cannot take it all.
  uint16 public constant MAX_PROTOCOL_FEE_BPS = 2_000;

  CoverNote public coverNote;
  SolventBook public solventBook; // optional aggregate floor; address(0) = per-market only
  address public immutable owner;
  /// @notice Share of every premium kept by the protocol, in bps. 0 = no fee (the default).
  uint16 public protocolFeeBps;
  /// @notice Where the protocol's share is sent at each purchase.
  address public feeRecipient;

  mapping(bytes32 strategyHash => Market) public markets;
  mapping(bytes32 strategyHash => bool) public registered;
  mapping(bytes32 strategyHash => uint256 notional) public outstanding;
  mapping(uint256 policyId => Policy) public policies;
  mapping(address underwriter => IReserveHook) public reserveHook; // optional yield-JIT hook
  mapping(bytes32 strategyHash => address) public premiumPricer; // optional external pricer (else RiskCurve)
  mapping(bytes32 strategyHash => BuyRules) public buyRules; // optional purchase rules
  mapping(uint256 policyId => uint64) public coverStart; // when cover begins (purchase + waiting period)
  mapping(bytes32 strategyHash => Episode) public openEpisode; // trigger true as of the last poke
  mapping(bytes32 strategyHash => Episode) public lastEpisode; // the most recent episode that ended
  uint256 public nextPolicyId;
  /// @notice Every registered market, so frontends/keepers enumerate state without log scans.
  bytes32[] public marketList;

  event MarketRegistered(bytes32 indexed strategyHash, address indexed underwriter, address indexed asset);
  event PolicyBought(
    uint256 indexed policyId,
    bytes32 indexed strategyHash,
    address indexed buyer,
    uint256 coverNotional,
    uint256 premium
  );
  event PolicyClaimed(uint256 indexed policyId, address indexed to, uint256 payout, uint256 price);
  event PolicyExpiredReleased(uint256 indexed policyId, bytes32 indexed strategyHash, uint256 coverNotional);
  event BuyRulesSet(bytes32 indexed strategyHash, uint64 minDuration, uint64 maxDuration, uint64 waitingPeriod);
  event TriggerSeen(bytes32 indexed strategyHash, uint256 payoutBps);
  event TriggerCleared(bytes32 indexed strategyHash, uint64 start, uint64 lastSeen, uint16 maxBps);
  event ProtocolFeeSet(uint16 feeBps, address indexed recipient);
  event ProtocolFeePaid(uint256 indexed policyId, address indexed asset, address indexed recipient, uint256 fee);

  error AlreadyInitialized();
  error NotOwner();
  error AlreadyRegistered();
  error NotUnderwriter();
  error UnknownMarket();
  error SolvencyFloorBreached(uint256 requested, uint256 available);
  error AggregateFloorBreached();
  error PolicyExpired();
  error PolicyNotExpired();
  error PolicyAlreadyClaimed();
  error NotNoteHolder();
  error StaleOracle();
  error NotDepegged(uint256 price, uint256 triggerPrice);
  error NotTriggered();
  error ZeroAmount();
  error FeeTooHigh(uint16 feeBps, uint16 maxBps);
  error ZeroFeeRecipient();
  error BadBuyRules();
  error DurationOutOfRange(uint64 duration, uint64 minDuration, uint64 maxDuration);
  error EventInProgress();
  error CoverNotStarted(uint64 startsAt);
  error NothingMoreDue();

  constructor(IAqua aqua, address _owner) AquaApp(aqua) {
    owner = _owner;
  }

  /// @notice One-time wiring of the CoverNote (deployed after CoverApp) and optional SolventBook.
  function initialize(CoverNote note, SolventBook book) external {
    if (msg.sender != owner) revert NotOwner();
    if (address(coverNote) != address(0)) revert AlreadyInitialized();
    coverNote = note;
    solventBook = book;
  }

  function setSolventBook(SolventBook book) external {
    if (msg.sender != owner) revert NotOwner();
    solventBook = book;
  }

  /// @notice Owner sets the protocol's share of each premium and where it goes. The share is taken
  ///         out of the premium, so the buyer's price does not change; the underwriter receives the
  ///         rest. Applies to purchases made after the call, never to policies already sold.
  function setProtocolFee(uint16 feeBps, address recipient) external {
    if (msg.sender != owner) revert NotOwner();
    if (feeBps > MAX_PROTOCOL_FEE_BPS) revert FeeTooHigh(feeBps, MAX_PROTOCOL_FEE_BPS);
    if (feeBps != 0 && recipient == address(0)) revert ZeroFeeRecipient();
    protocolFeeBps = feeBps;
    feeRecipient = recipient;
    emit ProtocolFeeSet(feeBps, recipient);
  }

  /// @notice The protocol's share of a given premium at the current fee.
  function protocolFeeOn(uint256 premium) public view returns (uint256) {
    return premium * protocolFeeBps / BPS;
  }

  /// @notice Underwriter registers an optional yield-JIT reserve hook for their own maker address.
  function setReserveHook(IReserveHook hook) external {
    reserveHook[msg.sender] = hook;
  }

  /// @notice Underwriter sets an external premium pricer for their market (else built-in RiskCurve).
  function setPremiumPricer(bytes32 strategyHash, address pricer) external {
    if (msg.sender != markets[strategyHash].underwriter) revert NotUnderwriter();
    premiumPricer[strategyHash] = pricer;
  }

  /// @notice Underwriter sets the purchase rules of their market: the shortest and longest term and
  ///         a waiting period before cover starts (0 = none). Applies to purchases made after the
  ///         call, never to policies already sold.
  function setBuyRules(bytes32 strategyHash, uint64 minDuration, uint64 maxDuration, uint64 waitingPeriod) external {
    if (msg.sender != markets[strategyHash].underwriter) revert NotUnderwriter();
    if (maxDuration != 0 && minDuration > maxDuration) revert BadBuyRules();
    buyRules[strategyHash] = BuyRules(minDuration, maxDuration, waitingPeriod);
    emit BuyRulesSet(strategyHash, minDuration, maxDuration, waitingPeriod);
  }

  // ── Underwriter
  // ──────────────────────────────────────────────────────────

  function registerMarket(Market calldata market) external returns (bytes32 strategyHash) {
    if (msg.sender != market.underwriter) revert NotUnderwriter();
    strategyHash = keccak256(abi.encode(market));
    if (registered[strategyHash]) revert AlreadyRegistered();
    // authenticates that the underwriter shipped exactly this strategy backing `market.asset`
    AQUA.safeBalances(market.underwriter, address(this), strategyHash, market.asset, market.asset);
    markets[strategyHash] = market;
    registered[strategyHash] = true;
    marketList.push(strategyHash);
    emit MarketRegistered(strategyHash, market.underwriter, market.asset);
  }

  // ── Views
  // ────────────────────────────────────────────────────────────────

  function backingOf(bytes32 strategyHash) public view returns (uint256 backing) {
    Market storage m = markets[strategyHash];
    (backing,) = AQUA.safeBalances(m.underwriter, address(this), strategyHash, m.asset, m.asset);
  }

  function capacityOf(bytes32 strategyHash) public view returns (uint256) {
    return backingOf(strategyHash) * markets[strategyHash].maxUtilBps / BPS;
  }

  /// @notice Premium for one year of `coverNotional` cover (the annual rate), at post-trade utilization.
  function quotePremium(bytes32 strategyHash, uint256 coverNotional) public view returns (uint256) {
    return quotePremiumFor(strategyHash, coverNotional, uint64(YEAR));
  }

  /// @notice Premium for `coverNotional` of cover over `duration` seconds: annual rate × term.
  function quotePremiumFor(bytes32 strategyHash, uint256 coverNotional, uint64 duration)
    public
    view
    returns (uint256)
  {
    uint256 capacity = capacityOf(strategyHash);
    if (capacity == 0) return 0;
    return _premium(strategyHash, coverNotional, outstanding[strategyHash] + coverNotional, capacity) * duration / YEAR;
  }

  /// @dev Premium via the market's external pricer if set, else the built-in RiskCurve.
  function _premium(bytes32 strategyHash, uint256 coverNotional, uint256 newOutstanding, uint256 capacity)
    internal
    view
    returns (uint256)
  {
    address p = premiumPricer[strategyHash];
    if (p != address(0)) return IPremiumPricer(p).quote(strategyHash, coverNotional, newOutstanding, capacity);
    Market storage m = markets[strategyHash];
    return RiskCurve.premium(coverNotional, m.startRateWad, m.endRateWad, m.convexityWad, newOutstanding * WAD / capacity);
  }

  function marketCount() external view returns (uint256) {
    return marketList.length;
  }

  function solvency(bytes32 strategyHash)
    external
    view
    returns (uint256 backing, uint256 covered, uint256 utilizationBps)
  {
    backing = backingOf(strategyHash);
    covered = outstanding[strategyHash];
    utilizationBps = backing == 0 ? 0 : covered * BPS / backing;
  }

  // ── Buyer
  // ────────────────────────────────────────────────────────────────

  /// @notice Buy cover, minting the CoverNote to msg.sender.
  function buyPolicy(bytes32 strategyHash, uint256 coverNotional, uint64 duration) external returns (uint256 policyId) {
    return _buy(strategyHash, coverNotional, duration, msg.sender);
  }

  /// @notice Buy cover, minting the CoverNote to `to` (used by the CoverRouter for routed buys).
  ///         Premium is always pulled from msg.sender.
  function buyPolicyFor(bytes32 strategyHash, uint256 coverNotional, uint64 duration, address to)
    external
    returns (uint256 policyId)
  {
    return _buy(strategyHash, coverNotional, duration, to);
  }

  function _buy(bytes32 strategyHash, uint256 coverNotional, uint64 duration, address to)
    internal
    returns (uint256 policyId)
  {
    if (!registered[strategyHash]) revert UnknownMarket();
    if (coverNotional == 0 || duration == 0) revert ZeroAmount();
    Market storage m = markets[strategyHash];

    BuyRules memory r = buyRules[strategyHash];
    if (duration < r.minDuration || (r.maxDuration != 0 && duration > r.maxDuration)) {
      revert DurationOutOfRange(duration, r.minDuration, r.maxDuration);
    }
    // No cover for a fire that is already burning: refuse while the trigger is true, or while an
    // episode recorded by `poke` has not been seen to end.
    (bool hit,) = marketTrigger(strategyHash);
    if (hit || openEpisode[strategyHash].start != 0) revert EventInProgress();

    uint256 capacity = capacityOf(strategyHash);
    uint256 newOutstanding = outstanding[strategyHash] + coverNotional;
    if (newOutstanding > capacity) revert SolvencyFloorBreached(newOutstanding, capacity);

    // Optional aggregate (cross-market) floor from the attestor-fed SolventBook.
    if (address(solventBook) != address(0)) {
      if (solventBook.headroom(m.underwriter, m.asset) < coverNotional) revert AggregateFloorBreached();
    }

    uint256 premium = _premium(strategyHash, coverNotional, newOutstanding, capacity) * duration / YEAR;

    // Pull premium from buyer; the protocol keeps its share and the rest is pushed into the
    // underwriter's Aqua reserve.
    uint256 fee = protocolFeeOn(premium);
    IERC20(m.asset).safeTransferFrom(msg.sender, address(this), premium);
    if (fee > 0) IERC20(m.asset).safeTransfer(feeRecipient, fee);
    IERC20(m.asset).forceApprove(address(AQUA), premium - fee);
    AQUA.push(m.underwriter, address(this), strategyHash, m.asset, premium - fee);

    outstanding[strategyHash] = newOutstanding;
    policyId = nextPolicyId++;
    policies[policyId] = Policy({
      marketHash: strategyHash, 
      coverNotional: coverNotional, 
      expiry: uint64(block.timestamp) + r.waitingPeriod + duration,
      claimed: false,
      buyer: to,
      boughtAt: uint64(block.timestamp),
      premium: premium,
      paidOut: 0
    });
    if (r.waitingPeriod > 0) coverStart[policyId] = uint64(block.timestamp) + r.waitingPeriod;
    coverNote.mint(to, policyId, 1);
    emit PolicyBought(policyId, strategyHash, to, coverNotional, premium);
    if (fee > 0) emit ProtocolFeePaid(policyId, m.asset, feeRecipient, fee);
  }

  // ── Claim
  // ────────────────────────────────────────────────────────────────

  /// @notice Claim if the insured event has occurred (built-in depeg, or an external trigger
  ///         product). Pays the CoverNote holder atomically from the underwriter's reserve.
  function claim(uint256 policyId) external returns (uint256 payout) {
    if (coverNote.balanceOf(msg.sender, policyId) == 0) revert NotNoteHolder();
    return _settle(policyId, msg.sender);
  }

  /// @notice Auto-payout: anyone (a keeper bot, a friend, the underwriter) can fire a triggered
  ///         policy, and the payout goes to whoever holds the note right now. The airbag deploys
  ///         itself — the insured never has to show up to claim.
  function payout(uint256 policyId) external returns (uint256) {
    address holder = coverNote.holderOf(policyId);
    if (holder == address(0)) revert NotNoteHolder();
    return _settle(policyId, holder);
  }

  /// @dev Pays what is due and not yet paid. A policy pays the deepest payout fraction seen during
  ///      its cover: live now, or recorded by `poke`. A proportional payout fired early is therefore
  ///      not final: if the loss deepens later in the term, the difference is paid then. The policy
  ///      closes (note burned, capacity released) once it has paid in full or its term is over.
  function _settle(uint256 policyId, address holder) internal returns (uint256 amount) {
    Policy storage p = policies[policyId];
    if (p.claimed) revert PolicyAlreadyClaimed();
    uint64 from = startOf(policyId);
    if (block.timestamp < from) revert CoverNotStarted(from);
    bool ended = block.timestamp > p.expiry;
    if (block.timestamp > uint256(p.expiry) + CLAIM_GRACE) revert PolicyExpired();

    Market storage m = markets[p.marketHash];
    uint256 payoutBps = _recordedBps(p.marketHash, from, p.expiry);
    // a live reading counts unless it belongs to an episode that began before cover started
    uint64 openStart = openEpisode[p.marketHash].start;
    if (!ended && (openStart == 0 || openStart >= from)) {
      (bool hit, uint256 live) = _liveTrigger(m, p.marketHash, policyId);
      if (hit && live > payoutBps) payoutBps = live;
    }
    if (payoutBps == 0) {
      if (ended) revert PolicyExpired();
      _evaluateTrigger(m, p.marketHash, policyId); // reverts with the reason nothing is due
    }

    uint256 due = p.coverNotional * payoutBps / BPS;
    if (due <= p.paidOut) revert NothingMoreDue();
    amount = due - p.paidOut;
    p.paidOut = due;
    // outstanding tracks what may still be paid: drop what is paid now, and the rest if this closes it
    uint256 release = amount;
    if (due == p.coverNotional || ended) {
      release += p.coverNotional - due;
      p.claimed = true;
      coverNote.burn(holder, policyId, 1);
    }
    outstanding[p.marketHash] -= release;

    // yield-JIT: let a registered reserve hook top up liquid balance before the pull
    IReserveHook hook = reserveHook[m.underwriter];
    if (address(hook) != address(0)) hook.onBeforePull(m.asset, amount);

    // pull payout from the underwriter's wallet to the note holder (atomic; reverts if unbacked)
    AQUA.pull(m.underwriter, p.marketHash, m.asset, amount, holder);
    emit PolicyClaimed(policyId, holder, amount, payoutBps);
  }

  // ── Expiry
  // ───────────────────────────────────────────────────────────────

  /// @notice Settle a policy that lapsed: releases what it can no longer pay so the underwriter's
  ///         capacity frees up (they keep the premium). Permissionless — anyone (a keeper, the
  ///         underwriter) can call it once the policy is past expiry. If an event was recorded
  ///         during its cover, it waits until the claim grace period is over.
  function expire(uint256 policyId) external {
    Policy storage p = policies[policyId];
    if (p.coverNotional == 0) revert UnknownMarket();
    if (p.claimed) revert PolicyAlreadyClaimed();
    if (block.timestamp <= p.expiry) revert PolicyNotExpired();
    if (
      _recordedBps(p.marketHash, startOf(policyId), p.expiry) * p.coverNotional / BPS > p.paidOut
        && block.timestamp <= uint256(p.expiry) + CLAIM_GRACE
    ) revert PolicyNotExpired();

    uint256 release = p.coverNotional - p.paidOut;
    p.claimed = true; // settled; the lapsed note can no longer claim
    outstanding[p.marketHash] -= release;
    emit PolicyExpiredReleased(policyId, p.marketHash, release);
  }

  // ── Trigger state
  // ────────────────────────────────────────────────────────

  /// @notice When a policy's cover begins: its purchase, plus the market's waiting period then.
  function startOf(uint256 policyId) public view returns (uint64) {
    uint64 s = coverStart[policyId];
    return s != 0 ? s : policies[policyId].boughtAt;
  }

  /// @notice Is the market's trigger true right now, and for what payout fraction? Market-level:
  ///         a trigger that depends on the policy (LP loss) reports false here. Never reverts;
  ///         a stale price reads as not triggered.
  function marketTrigger(bytes32 strategyHash) public view returns (bool hit, uint256 payoutBps) {
    return _liveTrigger(markets[strategyHash], strategyHash, type(uint256).max);
  }

  /// @notice Record the market's trigger state. Anyone (the keeper, a buyer, a watcher) may call it,
  ///         as often as they like. While the trigger is true it extends the open episode; once it
  ///         is false it closes it. Policies whose cover overlaps an episode can be paid for it,
  ///         even after the price recovers, and up to `CLAIM_GRACE` after they expire.
  function poke(bytes32 strategyHash) external {
    if (!registered[strategyHash]) revert UnknownMarket();
    Market storage m = markets[strategyHash];
    if (m.trigger == address(0)) {
      (uint256 price, uint256 updatedAt) = IPriceOracle(m.oracle).latestPrice();
      if (price == 0 || block.timestamp - updatedAt > m.oracleTimeout) revert StaleOracle();
    }
    (bool hit, uint256 bps) = marketTrigger(strategyHash);
    Episode storage e = openEpisode[strategyHash];
    if (hit) {
      if (e.start == 0) e.start = uint64(block.timestamp);
      e.lastSeen = uint64(block.timestamp);
      if (bps > e.maxBps) e.maxBps = uint16(bps);
      emit TriggerSeen(strategyHash, bps);
    } else if (e.start != 0) {
      lastEpisode[strategyHash] = e;
      emit TriggerCleared(strategyHash, e.start, e.lastSeen, e.maxBps);
      delete openEpisode[strategyHash];
    }
  }

  /// @dev Deepest payout fraction recorded in an episode that began within [from, to]. An episode
  ///      that began before cover started (in the waiting period) is not covered.
  function _recordedBps(bytes32 strategyHash, uint64 from, uint64 to) internal view returns (uint256 bps) {
    Episode memory e = openEpisode[strategyHash];
    if (e.start >= from && e.start <= to) bps = e.maxBps;
    e = lastEpisode[strategyHash];
    if (e.start >= from && e.start <= to && e.maxBps > bps) bps = e.maxBps;
  }

  /// @dev The trigger's answer now, without reverting. A stale price or a failing trigger is "no".
  function _liveTrigger(Market storage m, bytes32 marketHash, uint256 policyId)
    internal
    view
    returns (bool hit, uint256 payoutBps)
  {
    if (m.trigger == address(0)) {
      (uint256 price, uint256 updatedAt) = IPriceOracle(m.oracle).latestPrice();
      if (price == 0 || block.timestamp - updatedAt > m.oracleTimeout) return (false, 0);
      if (price > m.pegPrice * (BPS - m.depegBps) / BPS) return (false, 0);
      return (true, BPS);
    }
    try ITrigger(m.trigger).check(marketHash, policyId) returns (bool ok, uint256 bps) {
      if (!ok || bps == 0) return (false, 0);
      return (true, bps > BPS ? BPS : bps);
    } catch {
      return (false, 0);
    }
  }

  /// @dev Returns the payout fraction (bps) if triggered, else reverts.
  function _evaluateTrigger(Market storage m, bytes32 marketHash, uint256 policyId)
    internal
    view
    returns (uint256 payoutBps)
  {
    if (m.trigger == address(0)) {
      // built-in depeg: pay in full when the oracle price crosses the band
      (uint256 price, uint256 updatedAt) = IPriceOracle(m.oracle).latestPrice();
      if (price == 0 || block.timestamp - updatedAt > m.oracleTimeout) revert StaleOracle();
      uint256 triggerPrice = m.pegPrice * (BPS - m.depegBps) / BPS;
      if (price > triggerPrice) revert NotDepegged(price, triggerPrice);
      return BPS;
    }
    (bool ok, uint256 bps) = ITrigger(m.trigger).check(marketHash, policyId);
    if (!ok) revert NotTriggered();
    return bps > BPS ? BPS : bps;
  }
}
