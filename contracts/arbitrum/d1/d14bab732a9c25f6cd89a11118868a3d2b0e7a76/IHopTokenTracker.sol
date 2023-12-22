// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IHopTokenTracker {

    struct Swap {
        uint256 initialA;
        uint256 futureA;
        uint256 initialATime;
        uint256 futureATime;
        uint256 swapFee;
        uint256 adminFee;
        uint256 defaultWithdrawFee;
        address lpToken;
    }

    function swapStorage() external returns (Swap memory);

    function addLiquidity(uint256[] memory amounts, uint256 minMintAmount, uint256 deadline) external;

    function removeLiquidity(uint256 amount, uint256[] memory minAmounts, uint256 deadline) external;

    function getTokenIndex(address token) external view returns (uint8);

    function swap(uint8 tokenIndexFrom, uint8 tokenIndexTo, uint256 dx, uint256 minDy, uint256 deadline) external;

    function calculateRemoveLiquidity(address account, uint256 amount) external view returns (uint256[] memory);

    function calculateSwap(uint8 tokenIndexFrom, uint8 tokenIndexTo, uint256 dx) external view returns (uint256);

    function calculateTokenAmount(address account, uint256[] memory amounts, bool deposit) external view returns (uint256);
}

