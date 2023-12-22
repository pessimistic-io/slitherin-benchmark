// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface PriorityPoolEventError {
    // ---------------------------------------------------------------------------------------- //
    // *************************************** Events ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    event StakedLiquidity(uint256 amount, address sender);
    event UnstakedLiquidity(uint256 amount, address sender);
    event Liquidation(uint256 amount, uint256 generation);

    event NewGenerationLPTokenDeployed(
        string poolName,
        uint256 poolId,
        uint256 currentGeneration,
        string name,
        address newLPAddress
    );

    event CoverIndexChanged(uint256 oldIndex, uint256 newIndex);

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Errors ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    error PriorityPool__OnlyExecutor();
    error PriorityPool__OnlyPolicyCenter();
    error PriorityPool__NotOwnerOrFactory();
    error PriorityPool__WrongLPToken();
    error PriorityPool__WrongCoverLength();
    error PriorityPool__UnderMinCoverAmount();
}

