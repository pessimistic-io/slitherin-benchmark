// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AutomationCompatibleInterface} from "./AutomationCompatibleInterface.sol";

/**
 * @title IL2RobotKeeper
 * @author BGD Labs
 * @notice Defines the interface for the contract to automate actions on aave governance v2 bridge executors.
 */
interface IL2RobotKeeper is AutomationCompatibleInterface {
  /**
   * @dev Emitted when performUpkeep is called and actions are executed.
   * @param id actionsSetId id of successful action.
   * @param action successful action performed on the actionsSetId.
   */
  event ActionSucceeded(uint256 indexed id, ProposalAction indexed action);

  /**
   * @notice Actions that can be performed by the robot on the bridge executor.
   * @param PerformExecute: performs execute action on the bridge executor.
   */
  enum ProposalAction {
    PerformExecute
  }

  /**
   * @notice holds action to be performed for a given actionsSetId.
   * @param id actionsSetId for which action needs to be performed.
   * @param action action to be perfomed for the actionsSetId.
   */
  struct ActionWithId {
    uint256 id;
    ProposalAction action;
  }

  /**
   * @notice method called by owner / robot guardian to disable/enabled automation on a specific actionsSetId.
   * @param actionsSetId id for which we need to disable/enable automation.
   */
  function toggleDisableAutomationById(uint256 actionsSetId) external;

  /**
   * @notice method to check if automation for the actionsSetId is disabled/enabled.
   * @param actionsSetId id to check if automation is disabled or not.
   * @return bool if automation for actionsSetId is disabled or not.
   */
  function isDisabled(uint256 actionsSetId) external view returns (bool);

  /**
   * @notice method to get the address of the aave bridge executor contract.
   * @return bridge executor contract address.
   */
  function BRIDGE_EXECUTOR() external returns (address);

  /**
   * @notice method to get the max size of actions array, which is used for randomization of action execution.
   * also note that the maximum number of execute actions in one performUpkeep is always one.
   * @return max size of execute actions array to be used for randomization.
   */
  function MAX_ACTIONS() external returns (uint256);

  /**
   * @notice method to get maximum number of actionsSet to check before the latest actionsSet, if an action could be performed upon.
   * @return max number of skips.
   */
  function MAX_SKIP() external returns (uint256);
}

