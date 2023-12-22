// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {IPriceRiskModule} from "./IPriceRiskModule.sol";
import {IERC721EnumerableUpgradeable} from "./extensions_IERC721EnumerableUpgradeable.sol";

/**
 * @title IPayoutAutomation interface
 * @dev Interface for payout automations for the price risk modules
 * @author Ensuro
 */
interface IPayoutAutomation is IERC721EnumerableUpgradeable {
  /**
   * @dev Creates a new policy in a given PriceRiskModule
   *
   * Requirements:
   * - The oracle(s) are functional, returning non zero values and updated after (block.timestamp - oracleTolerance())
   * - The price jump is supported (_cdf[duration][priceJump] != 0)
   * - Spending approval granted to this contract
   *
   * @param riskModule   The PriceRiskModule where the policy will be created
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
    IPriceRiskModule riskModule,
    uint256 triggerPrice,
    bool lower,
    uint256 payout,
    uint40 expiration,
    address onBehalfOf
  ) external returns (uint256);

  /**
   * @dev Creates a new policy in a given PriceRiskModule (using ERC20 permit)
   *
   * Requirements:
   * - The oracle(s) are functional, returning non zero values and updated after (block.timestamp - oracleTolerance())
   * - The price jump is supported (_cdf[duration][priceJump] != 0)
   *
   * @param riskModule   The PriceRiskModule where the policy will be created
   * @param triggerPrice The price at which the policy should trigger.
   *                     If referenceOracle() != address(0), the price is expressed in terms of the reference asset,
   *                     with the same decimals as reported by the reference oracle
   *                     If referenceOracle() == address(0), the price is expressed in the denomination
   *                     of assetOracle(), with the same decimals.
   * @param lower If true -> triggers if the price is lower, If false -> triggers if the price is higher
   * @param payout Expressed in policyPool.currency()
   * @param expiration The policy expiration timestamp
   * @param onBehalfOf The address that will own the new policy
   * @param permitValue The value of the permit. Must be >= the policy premium
   * @param permitDeadline The deadline used in the signed permit
   * @param permitV The V component of the permit signature
   * @param permitR The R component of the permit signature
   * @param permitS The S component of the permit signature
   * @return policyId
   */
  function newPolicyWithPermit(
    IPriceRiskModule riskModule,
    uint256 triggerPrice,
    bool lower,
    uint256 payout,
    uint40 expiration,
    address onBehalfOf,
    uint256 permitValue,
    uint256 permitDeadline,
    uint8 permitV,
    bytes32 permitR,
    bytes32 permitS
  ) external returns (uint256);
}

