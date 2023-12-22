// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

abstract contract Logic {
    error NotImplemented();

    function claimRewards(address recipient) external virtual {
        revert NotImplemented();
    }

    function emergencyExit() external virtual {
        revert NotImplemented();
    }

    function enter() external virtual;

    function exit(uint256 liquidity) external virtual;

    function withdrawLiquidity(
        address recipient,
        uint256 amount
    ) external virtual;

    function accountLiquidity(
        address account
    ) external view virtual returns (uint256);
}

