// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IFlashLoanSimpleReceiver} from "./IFlashLoanSimpleReceiver.sol";

interface ILeverageHelper is IFlashLoanSimpleReceiver {
    enum InterestRateMode {
        STABLE,
        VARAIBLE
    }

    /// @notice Opens a leverage position on MahaLend
    /// @param assetToSupply The asset to supply (taken from the user)
    /// @param assetToLeverage The asset to leverage upon on MahaLend
    /// @param assetToBorrow The asset to borrow from MahaLend and sell to get exposure to more of the leveraged asset
    /// @param principalAmount How much `assetToSupply` is being provided
    /// @param minLeverageAssetExposure How much minimum `assetToLeverage` the user should be exposed to
    /// @param extraParams any extra params that need to be passed onto the contract
    function openPosition(
        address assetToSupply,
        address assetToLeverage,
        address assetToBorrow,
        uint256 principalAmount,
        uint256 minLeverageAssetExposure,
        bytes memory extraParams
    ) external;

    function closePosition(
        address assetToReceive,
        address assetToLeverage,
        address assetToRepay,
        uint256 leverageAssetExposure,
        uint256 minPrincipalAmount,
        bytes memory extraParams
    ) external;

    /// @notice get the leverage position of a given user
    /// @param who The user who opened the leverage position
    /// @param leverageAsset The asset to check for leverage
    /// @param debtAsset The asset to check for any debt
    /// @return leverageAssetExposure How much exposure the user has
    /// @return borrowedAmount How much debt the user has in the debt asset amount.
    /// @return healthFactor The health factor of this position. (A HF < 1 means the user will get liquidated).
    function position(
        address who,
        address leverageAsset,
        address debtAsset
    )
        external
        view
        returns (
            uint256 leverageAssetExposure,
            uint256 borrowedAmount,
            uint256 healthFactor
        );
}

