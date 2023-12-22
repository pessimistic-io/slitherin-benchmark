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
    uint8 public immutable decimals;

    receive() external payable {}

    function validateTimestamp(uint256) external view virtual override returns (bool);

    function getPrice() external view virtual override returns (uint256 price, uint256 timestamp);

    function updatePrice(
        bytes[] calldata updateData
    ) external payable virtual override returns (uint256 price, uint256 timestamp);

    /**
     * @notice Returns whether or not the contract is currently paused.
     * @return bool Returns true if the contract is paused.
     */
    function paused() public view override(Pausable, IOracleConnector) returns (bool) {
        return super.paused();
    }

    /**
     * @notice Constructor for OracleConnector.
     * @param name_ The name of the oracle.
     * @param decimals_ The number of decimal places in the price data.
     */
    constructor(string memory name_, uint8 decimals_) Ownable() Pausable() {
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

    function withdraw(uint256 amount) external onlyOwner returns (bool success) {
        (success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "OracleConnector: Transfer failed");
    }
}

