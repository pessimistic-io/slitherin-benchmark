// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {IPolicyPool} from "./IPolicyPool.sol";
import {IPremiumsAccount} from "./IPremiumsAccount.sol";
import {IAccessManager} from "./IAccessManager.sol";
import {RiskModule} from "./RiskModule.sol";
import {Policy} from "./Policy.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {IPriceRiskModule} from "./IPriceRiskModule.sol";
import {IPriceOracle} from "./IPriceOracle.sol";

/**
 * @title PriceRiskModule
 * @dev Risk Module that triggers the payout if the price of an asset is lower or higher than trigger price
 * @custom:security-contact security@ensuro.co
 * @author Ensuro
 */
contract PriceRiskModule is RiskModule, IPriceRiskModule {
  using WadRayMath for uint256;

  bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");
  bytes32 public constant PRICER_ROLE = keccak256("PRICER_ROLE");

  uint8 public constant PRICE_SLOTS = 30;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  uint256 internal immutable _slotSize;

  struct PolicyData {
    Policy.PolicyData ensuroPolicy;
    uint256 triggerPrice;
    bool lower; // If true -> triggers if the price is lower, If false -> triggers if the price is higher
  }

  mapping(uint256 => PolicyData) internal _policies;

  // Duration (in hours) of the protection * (1 if lower else -1) => cummulative density function
  //   [0] = prob of ([0, infinite%)
  //   [1] = prob of ([1, infinite%)
  //   ...
  //   [PRICE_SLOTS - 1] = prob of ([PRICE_SLOTS - 1, -infinite%)
  mapping(int40 => SlotPricing[PRICE_SLOTS]) internal _cdf;

  struct State {
    uint64 internalId; // internalId used to identify created policies
    uint32 minDuration; // In seconds, the minimum time that must elapse before a policy can be triggered
    IPriceOracle oracle; // The contract that returns the current price of the asset
  }

  State internal _state;

  event NewPricePolicy(
    address indexed customer,
    uint256 policyId,
    uint256 triggerPrice,
    bool lower
  );

  /**
   * @dev Constructs the PriceRiskModule.
   *      Note that, although it's supported that assetOracle_ and  referenceOracle_ have different number
   *      of decimals, they're assumed to be in the same denomination. For instance, assetOracle_ could be
   *      WMATIC/ETH and referenceOracle_ could be for USDC/ETH.
   *      This cannot be validated by the contract, so be careful when constructing.
   *
   * @param policyPool_ The policyPool
   * @param slotSize_ Size of each percentage slot in the pdf function (in wad)
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    IPolicyPool policyPool_,
    IPremiumsAccount premiumsAccount_,
    uint256 slotSize_
  ) RiskModule(policyPool_, premiumsAccount_) {
    _slotSize = slotSize_;
  }

  /**
   * @dev Initializes the RiskModule
   * @param name_ Name of the Risk Module
   * @param collRatio_ Collateralization ratio to compute solvency requirement as % of payout (in wad)
   * @param ensuroPpFee_ % of pure premium that will go for Ensuro treasury (in wad)
   * @param srRoc_ return on capital paid to Senior LPs (annualized percentage - in wad)
   * @param maxPayoutPerPolicy_ Maximum payout per policy (in wad)
   * @param exposureLimit_ Max exposure (sum of payouts) to be allocated to this module (in wad)
   * @param wallet_ Address of the RiskModule provider
   * @param oracle_ The contract that returns the current price of the asset
   */
  function initialize(
    string memory name_,
    uint256 collRatio_,
    uint256 ensuroPpFee_,
    uint256 srRoc_,
    uint256 maxPayoutPerPolicy_,
    uint256 exposureLimit_,
    address wallet_,
    IPriceOracle oracle_
  ) public initializer {
    __RiskModule_init(
      name_,
      collRatio_,
      ensuroPpFee_,
      srRoc_,
      maxPayoutPerPolicy_,
      exposureLimit_,
      wallet_
    );
    require(address(oracle_) != address(0), "PriceRiskModule: oracle_ cannot be the zero address");
    _state = State({internalId: 1, oracle: oracle_, minDuration: 3600});
  }

  /**
   * @dev Creates a new policy
   *
   * Requirements:
   * - The oracle(s) are functional, returning non zero values and updated after (block.timestamp - oracleTolerance())
   * - The price jump is supported (_cdf[duration][priceJump] != 0)
   *
   * @param triggerPrice The price at which the policy should trigger.
   *                     If referenceOracle() != address(0), the price is expressed in terms of the reference asset,
   *                     with the same decimals as reported by the reference oracle
   *                     If referenceOracle() == address(0), the price is expressed in the denomination
   *                     of assetOracle(), with the same decimals.
   * @param lower If true -> triggers if the price is lower, If false -> triggers if the price is higher
   * @param payout Expressed in policyPool.currency()
   * @param expiration The policy expiration timestamp
   * @param onBehalfOf The address that will own the new policy
   * @return policyId
   */
  function newPolicy(
    uint256 triggerPrice,
    bool lower,
    uint256 payout,
    uint40 expiration,
    address onBehalfOf
  ) external override whenNotPaused returns (uint256) {
    require(onBehalfOf != address(0), "onBehalfOf cannot be the zero address");
    (uint256 premium, SlotPricing memory pricing) = pricePolicy(
      triggerPrice,
      lower,
      payout,
      expiration
    );
    require(premium > 0, "Either duration or percentage jump not supported");

    uint256 policyId = (uint256(uint160(address(this))) << 96) + _state.internalId;
    PolicyData storage priceRiskPolicy = _policies[policyId];
    Params memory params_ = params();
    params_.jrCollRatio = uint256(pricing.jrCollRatio);
    params_.collRatio = uint256(pricing.collRatio);
    priceRiskPolicy.ensuroPolicy = _newPolicyWithParams(
      payout,
      premium,
      uint256(pricing.lossProb),
      expiration,
      _msgSender(),
      onBehalfOf,
      _state.internalId,
      params_
    );
    _state.internalId += 1;
    priceRiskPolicy.triggerPrice = triggerPrice;
    priceRiskPolicy.lower = lower;
    emit NewPricePolicy(onBehalfOf, policyId, triggerPrice, lower);
    return policyId;
  }

  /**
   * @dev Triggers the payout of the policy (if conditions are met)
   *
   * Requirements:
   * - Policy was created more than `minDuration()` seconds ago
   * - The oracle(s) are functional, returning non zero values and updated after (block.timestamp - oracleTolerance())
   * - getCurrentPrice() <= policy.triggerPrice if policy.lower
   * - getCurrentPrice() >= policy.triggerPrice if not policy.lower
   *
   * @param policyId The id of the policy (as returned by `newPolicy(...)`
   */
  function triggerPolicy(uint256 policyId) external override whenNotPaused {
    PolicyData storage policy = _policies[policyId];
    require(
      (block.timestamp - policy.ensuroPolicy.start) >= _state.minDuration,
      "Too soon to trigger the policy"
    );
    uint256 currentPrice = oracle().getCurrentPrice();
    require(
      !policy.lower || currentPrice <= policy.triggerPrice,
      "Condition not met CurrentPrice > triggerPrice"
    );
    require(
      policy.lower || currentPrice >= policy.triggerPrice,
      "Condition not met CurrentPrice < triggerPrice"
    );

    _policyPool.resolvePolicy(policy.ensuroPolicy, policy.ensuroPolicy.payout);
    // Be aware that `_policies` is not deleted when a policy is resolved, so getPolicyData will keep returning
    // the policy information, despite the policy is no longer claimable. To check if the policy is active, you should
    // call PolicyPool.getPolicyHash(policyId) and if the output is bytes32(0), that means the policy is no longer
    // active.
  }

  function policyCanBeTriggered(uint256 policyId) external view returns (bool) {
    PolicyData storage policy = _policies[policyId];
    if ((block.timestamp - policy.ensuroPolicy.start) < _state.minDuration) return false;

    uint256 currentPrice = oracle().getCurrentPrice();
    if (!policy.lower && currentPrice < policy.triggerPrice) return false;
    if (policy.lower && currentPrice > policy.triggerPrice) return false;
    return true;
  }

  /**
   * @dev Calculates the premium and lossProb of a policy
   * @param triggerPrice The price at which the policy should trigger, in Wad, with the same reference as
   *                     oracle().getCurrentPrice()
   * @param lower If true -> triggers if the price is lower, If false -> triggers if the price is higher
   * @param payout Expressed in policyPool.currency()
   * @param expiration Expiration of the policy
   * @return premium Premium that needs to be paid
   * @return price SlotPricing struct with the loss probability of paying the maximum payout and collateralization
   *               levels
   */
  function pricePolicy(
    uint256 triggerPrice,
    bool lower,
    uint256 payout,
    uint40 expiration
  ) public view override returns (uint256 premium, SlotPricing memory price) {
    uint256 currentPrice = oracle().getCurrentPrice();
    require(
      (lower && currentPrice > triggerPrice) || (!lower && currentPrice < triggerPrice),
      "Price already at trigger value"
    );
    uint40 duration = expiration - uint40(block.timestamp);
    require(duration >= _state.minDuration, "The policy expires too soon");
    price = _computeLossProb(currentPrice, triggerPrice, duration);

    if (price.lossProb == 0) return (0, price);
    premium = getMinimumPremiumForPricing(payout, price, expiration);
    return (premium, price);
  }

  function _round(uint256 number, uint256 denominator) internal pure returns (uint256) {
    return (number + denominator / 2) / denominator;
  }

  function _computeLossProb(
    uint256 currentPrice,
    uint256 triggerPrice,
    uint40 duration
  ) internal view returns (SlotPricing memory) {
    int40 sign = currentPrice > triggerPrice ? int40(1) : int40(-1);
    SlotPricing[PRICE_SLOTS] storage pdf = _cdf[int40(uint40(_round(duration, 3600))) * sign];

    // Calculate the jump percentage as integer with symmetric rounding
    uint256 priceJump = triggerPrice.wadDiv(currentPrice);
    if (sign == 1) {
      // 1 - trigger/current
      priceJump = WadRayMath.WAD - priceJump;
    } else {
      // trigger/current - 1
      priceJump -= WadRayMath.WAD;
    }

    uint8 slot = uint8(_round(priceJump, _slotSize));

    if (slot >= PRICE_SLOTS) {
      return pdf[PRICE_SLOTS - 1];
    } else {
      return pdf[slot];
    }
  }

  /**
   * @dev Sets the probability distribution for a given duration
   * @param duration Duration of the policy in hours (simetric rounding) positive if probability of lower price
   *                 negative if probability of higher price
   * @param cdf Array where cdf[i] = prob of price lower/higher than i% of current price
   */
  function setCDF(int40 duration, SlotPricing[PRICE_SLOTS] calldata cdf)
    external
    onlyComponentRole(PRICER_ROLE)
    whenNotPaused
  {
    require(duration != 0, "|duration| < 1");
    for (uint256 i = 0; i < PRICE_SLOTS; i++) {
      require(
        cdf[i].lossProb == 0 ||
          (cdf[i].jrCollRatio <= WadRayMath.WAD &&
            cdf[i].collRatio <= WadRayMath.WAD &&
            cdf[i].jrCollRatio <= cdf[i].collRatio),
        "Validation: invalid collateralization ratios"
      );
      _cdf[duration][i] = cdf[i];
    }
    // Encodes the duration as uint256 in this way:
    // If positive, it stays as it is (1 --> 1)
    // If negative, adds type(uint40).max to the absolute number (-1 --> type(uint40).max + 1)
    uint256 durationParam = duration < 0
      ? uint256(type(uint40).max + uint256(uint40(-duration)))
      : uint256(uint40(duration));
    _parameterChanged(IAccessManager.GovernanceActions.rmFiller1, durationParam, false);
  }

  /**
   * @dev Sets the minimum duration before a policy can be triggered
   * @param minDuration_ The new minimum duration in seconds.
   */
  function setMinDuration(uint40 minDuration_)
    external
    onlyComponentRole(ORACLE_ADMIN_ROLE)
    whenNotPaused
  {
    _state.minDuration = uint32(minDuration_);
    _parameterChanged(IAccessManager.GovernanceActions.rmFiller2, uint256(minDuration_), false);
  }

  /**
   * @dev Changes the price oracle
   * @param oracle_ The new price oracle to use.
   */
  function setOracle(IPriceOracle oracle_)
    external
    onlyComponentRole(ORACLE_ADMIN_ROLE)
    whenNotPaused
  {
    require(address(oracle_) != address(0), "PriceRiskModule: oracle_ cannot be the zero address");
    _state.oracle = oracle_;
    _parameterChanged(
      IAccessManager.GovernanceActions.rmFiller3,
      uint256(uint160(address(oracle_))),
      false
    );
  }

  function getCDF(int40 duration) external view returns (SlotPricing[PRICE_SLOTS] memory ret) {
    for (uint256 i = 0; i < PRICE_SLOTS; i++) {
      ret[i] = _cdf[duration][i];
    }
    return ret;
  }

  function oracle() public view override returns (IPriceOracle) {
    return _state.oracle;
  }

  function minDuration() external view override returns (uint40) {
    return _state.minDuration;
  }

  function getMinimumPremiumForPricing(
    uint256 payout,
    SlotPricing memory pricing,
    uint40 expiration
  ) public view returns (uint256) {
    Params memory p = params();
    p.jrCollRatio = uint256(pricing.jrCollRatio);
    p.collRatio = uint256(pricing.collRatio);
    return _getMinimumPremium(payout, pricing.lossProb, expiration, p);
  }

  function getPolicyData(uint256 policyId) external view returns (PolicyData memory) {
    return _policies[policyId];
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[47] private __gap;
}

