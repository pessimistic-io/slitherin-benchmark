// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAaveCLRobotOperator} from "./IAaveCLRobotOperator.sol";
import {AaveV3Arbitrum, AaveV3ArbitrumAssets} from "./AaveV3Arbitrum.sol";
import {IERC20} from "./contracts_IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafeCast} from "./SafeCast.sol";

/**
 * @title ProposalPayloadArbitrumRobot
 * @author BGD Labs
 * @dev Proposal to fund Chainlink Keeper for Arbitrum Bridge Executor Automation (gov v2)
 * - Transfer aLink tokens from AAVE Collector to the bridge executor
 * - Withdraw aLink to get link token from the Aave v3 Pool
 * - Refill the Chainlink Keeper with link via the operator contract
 */
contract ProposalPayloadArbitrumRobot {
  using SafeERC20 for IERC20;
  using SafeCast for uint256;

  address public immutable ROBOT_OPERATOR;
  uint256 public immutable LINK_AMOUNT;
  uint256 public immutable KEEPER_ID;

  /**
   * @dev constructor of the proposal
   * @param keeperId the chainlink id of the pre-registered keeper.
   * @param robotOperator the address of the aave chainlink robot operator
   * @param amountToFund the amount of link tokens to fund the keeper
   */
  constructor(uint256 keeperId, address robotOperator, uint256 amountToFund) {
    KEEPER_ID = keeperId;
    ROBOT_OPERATOR = robotOperator;
    LINK_AMOUNT = amountToFund;
  }

  function execute() external {
    // transfer aLink from collector to the bridge executor
    AaveV3Arbitrum.COLLECTOR.transfer(
      address(AaveV3ArbitrumAssets.LINK_A_TOKEN),
      address(this),
      LINK_AMOUNT
    );

    // withdraw aLink from the Aave V3 Pool
    AaveV3Arbitrum.POOL.withdraw(AaveV3ArbitrumAssets.LINK_UNDERLYING, LINK_AMOUNT, address(this));

    // approve link to the operator in order to refill the keeper
    IERC20(AaveV3ArbitrumAssets.LINK_UNDERLYING).forceApprove(
      ROBOT_OPERATOR,
      LINK_AMOUNT
    );

    // refills the keeper with link
    IAaveCLRobotOperator(ROBOT_OPERATOR).refillKeeper(
      KEEPER_ID,
      LINK_AMOUNT.toUint96()
    );
  }
}

