// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title Strateg relayer interactions target
 * @notice Contract to inherit to 
 */
abstract contract StrategUserInteractionsTarget {

    address private userInteractions;

    error NotStrategUserInteractions();


    modifier onlyStrategUserInteractions() {
        if (msg.sender != userInteractions) revert NotStrategUserInteractions();
        _;
    }

    function _setStrategUserInteractions(address _userInteractions) internal {
        userInteractions = _userInteractions;
    }

    function _strategUserInteractions() internal view returns (address) {
        return userInteractions;
    }
}

