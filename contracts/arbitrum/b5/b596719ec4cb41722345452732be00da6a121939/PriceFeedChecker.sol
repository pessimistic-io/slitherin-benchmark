// SPDX-License-Identifier: BUSL-1.1

// (c) Gearbox Holdings, 2022

// This code was largely inspired by Gearbox Protocol

pragma solidity 0.8.18;

import {IPriceOracleExceptions} from "./IPriceOracle.sol";

/// @title Price Feed Checker
/// @author Gearbox
/// @notice Sanity checker for Chainlink price feed results
/// @dev All function calls are currently implemented
/// @custom:security-contact security@munchies.money
contract PriceFeedChecker is IPriceOracleExceptions {
  function _checkAnswer(
    uint80 roundID,
    int256 price,
    uint256 updatedAt,
    uint80 answeredInRound
  ) internal pure {
    if (price <= 0) revert ZeroPriceException(); // F:[PO-5]
    if (answeredInRound < roundID || updatedAt == 0)
      revert ChainPriceStaleException(); // F:[PO-5]
  }
}

