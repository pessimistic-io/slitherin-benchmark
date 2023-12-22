// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IHotpotRoute {
    /**
     * swap `fromToken` to `toToken`, both token must be HotpotToken
     * @param fromTokenAddr the address of `fromToken`
     * @param toTokenAddr the address of `toToken`
     * @param amount  the amount of `fromToken` that want to swap
     * @param minReturn the mininum amount of `toToken` that expect
     * @param to swap to who
     * @param deadline the deadline of transaction
     */
    function swap(
        address fromTokenAddr,
        address toTokenAddr,
        uint256 amount,
        uint256 minReturn,
        address to,
        uint256 deadline
    ) external;

    /**
     * get the amount of `toToken` after swap
     * @param fromTokenAddr the address of `fromToken`
     * @param toTokenAddr the address of `toToken`
     * @param amount  the amount of `fromToken` that want to swap
     * @return returnAmount the amount of `toToken` that will receive
     * @return raisingTokenAmount the amount of `raisingToken` that will use in swap
     */
    function getAmountOut(
        address fromTokenAddr,
        address toTokenAddr,
        uint256 amount
    ) external view returns (uint256 returnAmount, uint256 raisingTokenAmount);
}

