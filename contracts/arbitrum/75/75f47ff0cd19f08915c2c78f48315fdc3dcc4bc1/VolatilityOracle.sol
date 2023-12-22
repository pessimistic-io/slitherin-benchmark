// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import { Ownable } from "./Ownable.sol";

// Interfaces
import { IVolatilityOracle } from "./IVolatilityOracle.sol";

contract VolatilityOracle is Ownable, IVolatilityOracle {
  /*==== PUBLIC VARS ====*/

  uint256 public lastVolatility;
  uint256 public lastUpdatedTimestamp;

  /*==== EVENTS  ====*/

  event VolatilityUpdated(uint256 vols);

  /*==== SETTER FUNCTIONS (ONLY OWNER) ====*/

  /**
   * @notice Updates the last volatility for DPX
   * @param v volatility
   * @return volatility of dpx
   */
  function updateVolatility(uint256 v) external onlyOwner returns (uint256) {
    require(v != 0, "Volatility cannot be 0");

    lastVolatility = v;
    lastUpdatedTimestamp = block.timestamp;

    emit VolatilityUpdated(v);

    return v;
  }

  /*==== VIEWS ====*/

  /**
   * @notice Gets the volatility of dpx
   * @return volatility
   */
  function getVolatility(uint256) external view override returns (uint256) {
    require(lastVolatility != 0, "Last volatility == 0");

    return lastVolatility;
  }
}

