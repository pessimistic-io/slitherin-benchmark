// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./Ownable.sol";
import "./Pausable.sol";
import "./IOracleConnector.sol";

/**
 * @title OracleConnector
 * @notice Abstract contract for connecting to an oracle and retrieving price data.
 */
abstract contract OracleConnector is IOracleConnector, Ownable, Pausable {
    string public name;
    uint256 public immutable decimals;

    /**
     * @notice Validates a given timestamp.
     * @param timestamp The timestamp to validate.
     * @return bool Returns true if the timestamp is valid.
     */
    function validateTimestamp(uint256 timestamp) external view virtual returns (bool);

    /**
     * @notice Returns whether or not the contract is currently paused.
     * @return bool Returns true if the contract is paused.
     */
    function paused() public view override returns (bool) {
        return super.paused();
    }

    /**
     * @notice Retrieves the current price from the oracle.
     * @return uint256 Returns the current price.
     */
    function getPrice() external view virtual returns (uint256);

    /**
     * @notice Constructor for OracleConnector.
     * @param name_ The name of the oracle.
     * @param decimals_ The number of decimal places in the price data.
     */
    constructor(string memory name_, uint256 decimals_) Ownable() Pausable() {
        name = name_;
        decimals = decimals_;
    }

    /**
     * @notice Toggles the pause state of the contract.
     * @return bool Returns true if the pause state was successfully toggled.
     */
    function togglePause() external onlyOwner returns (bool) {
        if (paused()) _unpause();
        else _pause();
        return true;
    }
}

