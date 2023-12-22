// SPDX-License-Identifier: agpl-3.0
// OpenZeppelin Contracts (last updated v4.7.0) (governance/TimelockController.sol)

pragma solidity ^0.8.0;

import "./TimelockController.sol";
import "./GovernanceInitiationData.sol";

/**
 * @title CoraTimelockController
 * @dev Modified version of OpenZeppelin's TimelockController contract that includes a GovernanceInitiationData parameter to setup the governance.
 */
contract CoraTimelockController is TimelockController {
  constructor(
    uint256 minDelay,
    address[] memory proposers,
    address[] memory executors,
    GovernanceInitiationData _initiationData
  ) TimelockController(minDelay, proposers, executors, address(0)) {
    // @dev address(0) for non additional admins

    address governor = _initiationData.governorAddress();

    if (governor != address(0)) {
      _setupRole(PROPOSER_ROLE, governor);
      _setupRole(CANCELLER_ROLE, governor);
    }

    _setupRole(EXECUTOR_ROLE, address(0)); // Allow anybody to execute the proposals
  }
}

