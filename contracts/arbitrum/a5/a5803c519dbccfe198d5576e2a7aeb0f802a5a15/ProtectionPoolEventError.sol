// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface ProtectionPoolEventError {
    // ---------------------------------------------------------------------------------------- //
    // *************************************** Events ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    event LiquidityProvided(
        uint256 usdcAmount,
        uint256 lpAmount,
        address sender
    );
    event LiquidityRemoved(
        uint256 lpAmount,
        uint256 usdcAmount,
        address sender
    );

    event LiquidityRemovedWhenClaimed(address pool, uint256 amount);

    event RewardUpdated(uint256 totalReward);

    event PriceUpdated(uint256 price);

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Errors ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    error ProtectionPool__OnlyPolicyCenter();
    error ProtectionPool__ExceededTotalSupply();
    error ProtectionPool__OnlyPriorityPool();
    error ProtectionPool__NotEnoughLiquidity();
    error ProtectionPool__OnlyPriorityPoolOrPolicyCenter();
    error ProtectionPool__NotEnoughBalance();
    error ProtectionPool__NotAllowedToPause();

}
