// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface RewardRouter {
    function claimFromMlpUnwrap() external;
    function stakeMlp(uint256 _amount) external returns (uint256);
    function unstakeMlp(uint256 _amount) external returns (uint256);
}

interface OrderBook {
    function placeLiquidityOrder(
        uint8 assetId,
        uint96 rawAmount, // erc20.decimals
        bool isAdding
    ) external payable;
}

