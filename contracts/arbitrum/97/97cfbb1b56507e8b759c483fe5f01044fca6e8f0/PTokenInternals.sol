// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IPTokenInternals.sol";
import "./CTokenInterfaces.sol";

abstract contract PTokenInternals is IPTokenInternals {

    function _getExternalExchangeRate() internal virtual override returns (uint256 externalExchangeRate) {
        externalExchangeRate = 10**EXCHANGE_RATE_DECIMALS;
        if (currentExchangeRate != externalExchangeRate) currentExchangeRate = externalExchangeRate;
    }
}
