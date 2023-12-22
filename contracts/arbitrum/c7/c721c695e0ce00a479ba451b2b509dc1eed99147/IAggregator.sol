// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./ERC20_IERC20.sol";

import "./ISwapHandler.sol";

interface IAggregator is ISwapHandler {
    /* ========= EVENTS ========= */

    event TokensRescued(address indexed to, address indexed token, uint256 amount);

    /* ========= RESTRICTED ========= */

    function rescueFunds(
        IERC20 token_,
        address to_,
        uint256 amount_
    ) external;
}
