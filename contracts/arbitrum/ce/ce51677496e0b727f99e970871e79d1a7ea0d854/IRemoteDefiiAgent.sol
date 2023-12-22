// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IRemoteDefiiAgent {
    function increaseShareBalance(
        address vault,
        uint256 positionId,
        uint256 shares
    ) external;

    function withdrawLiquidity(address to, uint256 shares) external;
}

