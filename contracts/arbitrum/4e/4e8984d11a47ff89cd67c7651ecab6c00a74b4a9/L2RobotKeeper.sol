// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAaveGovernanceV2} from "./AaveGovernanceV2.sol";
import {IExecutorBase} from "./IExecutorBase.sol";
import {IL2RobotKeeper, AutomationCompatibleInterface} from "./IL2RobotKeeper.sol";
import {IAaveCLRobotOperator} from "./IAaveCLRobotOperator.sol";
import {Ownable} from "./Ownable.sol";

/**
 * @title L2RobotKeeper
 * @author BGD Labs
 * @dev Aave chainlink keeper-compatible contract for proposal actionsSet automation on layer 2:
 * - checks if the proposal actionsSet state could be moved to executed
 * - moves the proposal actionsSet to executed if all the conditions are met
 */
contract L2RobotKeeper is Ownable, IL2RobotKeeper {
  /// @inheritdoc IL2RobotKeeper
  address public immutable BRIDGE_EXECUTOR;

  /// @inheritdoc IL2RobotKeeper
  uint256 public constant MAX_ACTIONS = 25;

  /// @inheritdoc IL2RobotKeeper
  uint256 public constant MAX_SKIP = 20;

  mapping(uint256 => bool) internal _disabledActionsSets;

  error NoActionCanBePerformed();

  /**
   * @param bridgeExecutor address of the bridge executor contract.
   */
  constructor(address bridgeExecutor) {
    BRIDGE_EXECUTOR = bridgeExecutor;
  }

  /**
   * @inheritdoc AutomationCompatibleInterface
   * @dev run off-chain, checks if proposal actionsSet should be moved to executed state.
   */
  function checkUpkeep(bytes calldata) external view override returns (bool, bytes memory) {
    uint256[] memory actionsSetIdsToPerformExecute = new uint256[](MAX_ACTIONS);

    uint256 index = IExecutorBase(BRIDGE_EXECUTOR).getActionsSetCount();
    uint256 skipCount = 0;
    uint256 actionsCount = 0;

    // loops from the last/latest actionsSetId until MAX_SKIP iterations. resets skipCount and checks more MAX_SKIP number
    // of actionsSet if they could be executed. we only check actionsSet until MAX_SKIP iterations from the last/latest actionsSet
    // or actionsSets where any action could be performed, and actionsSets before that will not be checked by the keeper.
    while (index != 0 && skipCount <= MAX_SKIP && actionsCount <= MAX_ACTIONS) {
      uint256 actionsSetId = index - 1;

      if (!isDisabled(actionsSetId)) {
        if (_canActionSetBeExecuted(actionsSetId)) {
          skipCount = 0;
          actionsSetIdsToPerformExecute[actionsCount] = actionsSetId;
          actionsCount++;
        } else {
          // it is in final state: executed/expired/cancelled
          skipCount++;
        }
      }

      index--;
    }

    if (actionsCount > 0) {
      // we do not know the length in advance, so we init arrays with the maxNumberOfActions
      // and then squeeze the array using mstore
      assembly {
        mstore(actionsSetIdsToPerformExecute, actionsCount)
      }
      bytes memory performData = abi.encode(actionsSetIdsToPerformExecute);
      return (true, performData);
    }

    return (false, '');
  }

  /**
   * @inheritdoc AutomationCompatibleInterface
   * @dev if actionsSet could be executed - performs execute action on the bridge executor contract.
   * @param performData actionsSet ids to execute.
   */
  function performUpkeep(bytes calldata performData) external override {
    uint256[] memory actionsSetIds = abi.decode(performData, (uint256[]));
    bool isActionPerformed;

    // executes action on actionSetIds in order from first to last
    for (uint i = actionsSetIds.length; i > 0; i--) {
      uint256 actionsSetId = actionsSetIds[i - 1];

      if (_canActionSetBeExecuted(actionsSetId)) {
        try IExecutorBase(BRIDGE_EXECUTOR).execute(actionsSetId) {
          isActionPerformed = true;
          emit ActionSucceeded(actionsSetId, ProposalAction.PerformExecute);
        } catch Error(string memory reason) {
          emit ActionFailed(actionsSetId, ProposalAction.PerformExecute, reason);
        }
      }
    }

    if (!isActionPerformed) revert NoActionCanBePerformed();
  }

  /// @inheritdoc IL2RobotKeeper
  function toggleDisableAutomationById(
    uint256 actionsSetId
  ) external onlyOwner {
    _disabledActionsSets[actionsSetId] = !_disabledActionsSets[actionsSetId];
  }

  /// @inheritdoc IL2RobotKeeper
  function isDisabled(uint256 actionsSetId) public view returns (bool) {
    return _disabledActionsSets[actionsSetId];
  }

  /**
   * @notice method to check if the actionsSet could be executed.
   * @param actionsSetId the actionsSetId to check if it can be executed.
   * @return true if the actionsSet could be executed, false otherwise.
   */
  function _canActionSetBeExecuted(uint256 actionsSetId) internal view returns (bool) {
    IExecutorBase.ActionsSet memory actionsSet = IExecutorBase(BRIDGE_EXECUTOR).getActionsSetById(
      actionsSetId
    );
    IExecutorBase.ActionsSetState actionsSetState = IExecutorBase(BRIDGE_EXECUTOR).getCurrentState(
      actionsSetId
    );

    if (
      actionsSetState == IExecutorBase.ActionsSetState.Queued &&
      block.timestamp >= actionsSet.executionTime
    ) {
      return true;
    }
    return false;
  }
}

