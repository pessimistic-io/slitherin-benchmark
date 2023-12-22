// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./ILiquidityBox.sol";

interface ILiquidityPool is ILiquidityBox {
    function depositTokens(address, uint256) external;
    function withDrawAllTokens(address) external;
    function withDrawTokens(address, uint256) external;
}

