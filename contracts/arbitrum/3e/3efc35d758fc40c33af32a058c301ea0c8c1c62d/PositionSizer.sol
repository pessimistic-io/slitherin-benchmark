// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IStrategyVault} from "./IStrategyVault.sol";
import {VaultGetter} from "./VaultGetter.sol";
import {IErrors} from "./IErrors.sol";

library PositionSizer {
    //////////////////////////////////////////////
    //                 GETTER                   //
    //////////////////////////////////////////////

    function strategyCount() public pure returns (uint256) {
        return 4;
    }

    //////////////////////////////////////////////
    //                 EXTERNAL                 //
    //////////////////////////////////////////////
    /**
        @notice Fetches the weights for the vaults
        @dev If 1 then x% deployed in equalWeight or if 2 then x% deployed in customWeight. When 2, weights would
        return either fixed, cascading, or best return -- threshold could be assigned in these ways
        @param vaults the list of vaults to check
        @param epochIds the list of epochIds to check
        @param availableAmount the amount available to deposit
        @param weightStrategy the strategy to use for weights
     */
    function fetchWeights(
        address[] memory vaults,
        uint256[] memory epochIds,
        uint256 availableAmount,
        uint256 weightStrategy
    ) external view returns (uint256[] memory amounts) {
        if (weightStrategy == 1)
            return _equalWeight(availableAmount, vaults.length);
        else if (weightStrategy < strategyCount()) {
            uint256[] memory weights = _fetchWeight(
                vaults,
                epochIds,
                weightStrategy
            );
            return _customWeight(availableAmount, vaults, weights);
        } else revert IErrors.InvalidWeightStrategy();
    }

    //////////////////////////////////////////////
    //                 INTERNAL                 //
    //////////////////////////////////////////////
    /**
        @notice Assigns the available amount across the vaults
        @param availableAmount the amount available to deposit
        @param length the length of the vaults
        @return amounts The list of amounts to deposit in each vault
     */
    function _equalWeight(
        uint256 availableAmount,
        uint256 length
    ) private pure returns (uint256[] memory amounts) {
        amounts = new uint256[](length);

        uint256 modulo = availableAmount % length;
        for (uint256 i = 0; i < length; ) {
            amounts[i] = availableAmount / length;
            if (modulo > 0) {
                amounts[i] += 1;
                modulo -= 1;
            }
            unchecked {
                i++;
            }
        }
    }

    /**
        @notice Assigns the available amount in custom weights across the vaults
        @param availableAmount the amount available to deposit
        @param vaults the list of vaults to check
        @param customWeights the list of custom weights to check
        @return amounts The list of amounts to deposit in each vault
     */
    function _customWeight(
        uint256 availableAmount,
        address[] memory vaults,
        uint256[] memory customWeights
    ) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](vaults.length);
        for (uint256 i = 0; i < vaults.length; ) {
            uint256 weight = customWeights[i];
            if (weight == 0) amounts[i] = 0;
            else amounts[i] = (availableAmount * weight) / 10_000;
            unchecked {
                i++;
            }
        }
    }

    //////////////////////////////////////////////
    //            INTERNAL - WEIGHT MATH        //
    //////////////////////////////////////////////
    /**
        @notice Fetches the weights dependent on the strategy
        @param vaults the list of vaults to check
        @param epochIds the list of epochIds to check
        @param weightStrategy the strategy to use for weights
        @return weights The list of weights to use
     */
    function _fetchWeight(
        address[] memory vaults,
        uint256[] memory epochIds,
        uint256 weightStrategy
    ) internal view returns (uint256[] memory weights) {
        if (weightStrategy == 2) return _fixedWeight(vaults);
        if (weightStrategy == 3) return _thresholdWeight(vaults, epochIds);
    }

    /**
        @notice fetches the fixed weights from the strategy vault
        @param vaults the list of vaults to check
        @return weights The list of weights to use
     */
    function _fixedWeight(
        address[] memory vaults
    ) internal view returns (uint256[] memory weights) {
        weights = IStrategyVault(address(this)).fetchVaultWeights();
        if (weights.length != vaults.length) revert IErrors.LengthMismatch();
    }

    /**
        @notice Fetches the weights from strategy vault where appended value is threshold and rest are ids
        @dev Threshold assigns funds equally if threshold is passed
     */
    function _thresholdWeight(
        address[] memory vaults,
        uint256[] memory epochIds
    ) internal view returns (uint256[] memory weights) {
        uint256[] memory marketIds = IStrategyVault(address(this))
            .fetchVaultWeights();
        if (marketIds.length != vaults.length + 1)
            revert IErrors.LengthMismatch();

        // NOTE: Threshold is appended and weights are marketIds for V1 or empty for V2
        uint256 threshold = marketIds[marketIds.length - 1];
        weights = new uint256[](vaults.length);
        uint256[] memory validIds = new uint256[](vaults.length);
        uint256 validCount;

        for (uint256 i; i < vaults.length; ) {
            uint256 roi = _fetchReturn(vaults[i], epochIds[i], marketIds[i]);
            if (roi > threshold) {
                validCount += 1;
                validIds[i] = i;
            }
            unchecked {
                i++;
            }
        }
        if (validCount == 0) revert IErrors.NoValidThreshold();

        uint256 modulo = 10_000 % validCount;
        for (uint j; j < validCount; ) {
            uint256 location = validIds[j];
            weights[location] = 10_000 / validCount;
            if (modulo > 0) {
                weights[location] += 1;
                modulo -= 1;
            }
            unchecked {
                j++;
            }
        }
    }

    //////////////////////////////////////////////
    //            INTERNAL - ROI CALCS        //
    //////////////////////////////////////////////
    /**
        @notice Fetches the roi for a list of vaults
        @param vaults the list of vaults
        @param epochIds the list of epochIds
        @param marketIds the list of marketIds
        @return roi The list of rois
     */
    function _fetchReturns(
        address[] memory vaults,
        uint256[] memory epochIds,
        uint256[] memory marketIds
    ) internal view returns (uint256[] memory roi) {
        for (uint256 i = 0; i < vaults.length; ) {
            roi[i] = _fetchReturn(vaults[i], epochIds[i], marketIds[i]);
            unchecked {
                i++;
            }
        }
    }

    /**
        @notice Fetches the roi for a vault
        @param vault the vault  
        @param epochId the epochId to check
        @param marketId the marketId to check
        @return roi The roi for the vault
     */
    function _fetchReturn(
        address vault,
        uint256 epochId,
        uint256 marketId
    ) private view returns (uint256 roi) {
        return VaultGetter.getRoi(vault, epochId, marketId);
    }
}

