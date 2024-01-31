// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/// @title Scheduler Storage
/// @author Chain Labs
/// @notice Storage Contract of Scheduler to support upgradeablity
contract SchedulerStorage {
    /// @notice number of schmints executed
    /// @return schmintsExecuted number of schmints executed
    uint256 public schmintsExecuted;

    /// @notice counter to keep count of schmints
    /// @return schmintCounter number of schmints created
    uint256 public schmintCounter;

    /// @notice maps schmint ID with schmint details
    /// @dev mapping of schmint ID to schmint
    mapping(uint256 => Schmint) public schmints;

    /// @notice resolver address
    /// @dev Resolver contract that resolves multiple protocol states
    /// @return resolver address
    address public resolver;

    struct Schmint {
        bool isSchminted; // checks if the schmint has been executed or not
        bool isCancelled; // if the schmint is cancelled or not
        uint40 gasPriceLimit; // limit of gas price, if gas price above this value, schmint will not be executed
        address target; // where the schmint should happen
        bytes32 taskId; // gelato specific task ID
        uint256 value; // value to be sent to taret while schmintingx
        bytes data; // encoded with selector data to exectue schmint
    }
}

