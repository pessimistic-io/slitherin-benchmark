// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./PTokenStorage.sol";

abstract contract IPTokenInternals is PTokenStorage {//is IERC20 {

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @dev This excludes the value of the current message, if any
     * @return The quantity of underlying tokens owned by this contract
     */
    // function _getCashPrior() internal virtual view returns (uint256);

    /**
     * @notice Retrieves the exchange rate for a given token.
     * @dev Will always be 1 for non-IB/Rebase tokens.
     */
    function _getExternalExchangeRate() internal virtual returns (uint256 externalExchangeRate);
}

