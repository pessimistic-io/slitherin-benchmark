// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./interfaces_ISwapRouter.sol";

interface ISwapRouterWithWETH is ISwapRouter {
    function WETH9() external returns (address);
}

