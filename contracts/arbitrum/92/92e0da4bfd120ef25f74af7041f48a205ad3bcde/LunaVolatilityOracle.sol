// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {Ownable} from "./Ownable.sol";

contract LunaVolatilityOracle is Ownable {
    /*==== PUBLIC VARS ====*/

    uint256 public lastVolatility;

    uint256 public lastUpdatedAt;

    /*==== SETTER FUNCTIONS (ONLY OWNER) ====*/

    /**
     * @notice Updates the last volatility for LUNA
     * @param v volatility
     * @return volatility of LUNA
     */
    function updateVolatility(uint256 v) external onlyOwner returns (uint256) {
        require(v != 0, 'VolatilityOracle: Volatility cannot be 0');

        lastVolatility = v;

        lastUpdatedAt = block.timestamp;

        emit VolatilityUpdate(v, lastUpdatedAt);

        return v;
    }

    /*==== VIEWS ====*/

    /**
     * @notice Gets the volatility of LUNA
     * @return volatility
     */
    function getVolatility(uint256) external view returns (uint256) {
        require(lastVolatility != 0, 'VolatilityOracle: Last volatility == 0');

        return lastVolatility;
    }

    /*==== EVENTS ====*/

    event VolatilityUpdate(uint256 newVolatility, uint256 updatedAt);
}

