// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {IRiskModule} from "./IRiskModule.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {IPriceOracle} from "./IPriceOracle.sol";

/**
 * @title IPriceRiskModule interface
 * @dev Interface for price risk module
 * @author Ensuro
 */
interface IPriceRiskModule is IRiskModule {
  /**
   * @dev Struct that represents the pricing parameters for a given slot.
   *      Includes the lossProb (used to compute the pure premium) and the collateralization ratios
   */
  struct SlotPricing {
    uint64 lossProb;
    uint64 jrCollRatio;
    uint64 collRatio;
  }

  /**
   * @dev Returns the premium and lossProb of the policy
   * @param triggerPrice Price of the asset_ that will trigger the policy (expressed in _currency)
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
  ) external view returns (uint256 premium, SlotPricing memory price);

  function newPolicy(
    uint256 triggerPrice,
    bool lower,
    uint256 payout,
    uint40 expiration,
    address onBehalfOf
  ) external returns (uint256);

  function triggerPolicy(uint256 policyId) external;

  function policyCanBeTriggered(uint256 policyId) external view returns (bool);

  function oracle() external view returns (IPriceOracle);

  /**
   * @dev In seconds, the minimum time that must elapse before a policy can be triggered, since creation
   */
  function minDuration() external view returns (uint40);
}

