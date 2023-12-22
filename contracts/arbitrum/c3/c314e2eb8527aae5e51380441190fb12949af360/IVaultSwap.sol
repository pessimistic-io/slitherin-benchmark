// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;
pragma abicoder v2;
import "./IWETH9.sol";

interface IVaultSwap {
    event Swap(IERC20 sellToken, IERC20 buyToken, uint256 boughtAmount);

    struct SwapParams {
        // The `sellTokenAddress` field from the API response.
        IERC20 sellToken;
        // The amount of sellToken we want to sell
        uint256 sellAmount;
        // The `buyTokenAddress` field from the API response.
        IERC20 buyToken;
        // The `allowanceTarget` field from the API response.
        address spender;
        // The `to` field from the API response.
        address payable swapTarget;
        // The `data` field from the API response.
        bytes swapCallData;
    }

    receive() external payable;

    function swap(
        SwapParams calldata params
    ) external payable returns (uint256);
}

