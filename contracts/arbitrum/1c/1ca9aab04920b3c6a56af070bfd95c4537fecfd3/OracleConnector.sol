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
     * @notice Retrieves the data for a specific round ID.
     * @param roundId_ The ID of the round to retrieve data for.
     * @return roundId The round ID.
     * @return answer The answer for the round.
     * @return startedAt The timestamp when the round started.
     * @return updatedAt The timestamp when the round was last updated.
     * @return answeredInRound The round ID where the answer was computed.
     */
    function getRoundData(
        uint256 roundId_
    )
        external
        view
        virtual
        returns (uint256 roundId, uint256 answer, uint256 startedAt, uint256 updatedAt, uint256 answeredInRound);

    /**
     * @notice Retrieves the ID of the latest round.
     * @return The ID of the latest round.
     */
    function latestRound() external view virtual returns (uint256);

    /**
     * @notice Retrieves the data for the latest round.
     * @return roundId The round ID.
     * @return answer The answer for the round.
     * @return startedAt The timestamp when the round started.
     * @return updatedAt The timestamp when the round was last updated.
     * @return answeredInRound The round ID where the answer was computed.
     */
    function latestRoundData()
        external
        view
        virtual
        returns (uint256 roundId, uint256 answer, uint256 startedAt, uint256 updatedAt, uint256 answeredInRound);

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

