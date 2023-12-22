// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { IValuer } from "./IValuer.sol";
import { Registry } from "./Registry.sol";
import { VaultBaseExternal } from "./VaultBaseExternal.sol";
import { IGmxPositionRouter } from "./IGmxPositionRouter.sol";
import { IGmxRouter } from "./IGmxRouter.sol";
import { IGmxVault } from "./IGmxVault.sol";

import { GmxStoredData } from "./GmxStoredData.sol";
import { GmxHelpers } from "./GmxHelpers.sol";

import { Constants } from "./Constants.sol";

contract GmxValuer is IValuer {
    function getAssetValue(
        uint,
        address,
        int256
    ) external pure returns (uint256) {
        revert('Cannot value individual units');
    }

    function getVaultValue(
        address valioVault,
        address gmxVault, // asset
        int256 // unitPrice
    ) external view returns (uint256 value) {
        // Check for value locked in increaseRequests
        value += _calculateOutstandingRequestValue(valioVault);

        GmxStoredData.GMXPositionData[] memory positions = GmxStoredData
            .getStoredPositions(valioVault);
        value += _calculateAllPositionsValue(
            valioVault,
            IGmxVault(gmxVault),
            positions
        );
    }

    function _calculateAllPositionsValue(
        address valioVault,
        IGmxVault gmxVault,
        GmxStoredData.GMXPositionData[] memory positions
    ) internal view returns (uint256 value) {
        for (uint i = 0; i < positions.length; i++) {
            value += calculatePositionValue(valioVault, gmxVault, positions[i]);
        }
    }

    function calculatePositionValue(
        address valioVault,
        IGmxVault gmxVault,
        GmxStoredData.GMXPositionData memory keyData
    ) public view returns (uint256 value) {
        (
            uint256 size,
            uint collateral,
            ,
            uint entryFundingRate,
            ,
            ,
            ,

        ) = IGmxVault(gmxVault).getPosition(
                valioVault,
                keyData._collateralToken,
                keyData._indexToken,
                keyData._isLong
            );

        if (size == 0) {
            return 0;
        }

        bool hasProfit;
        uint delta;
        (hasProfit, delta) = IGmxVault(gmxVault).getPositionDelta(
            valioVault,
            keyData._collateralToken,
            keyData._indexToken,
            keyData._isLong
        );

        if (!hasProfit && delta > collateral) {
            return (0);
        }

        value = hasProfit ? collateral + delta : collateral - delta;

        uint fundingFee = IGmxVault(gmxVault).getFundingFee(
            keyData._collateralToken,
            size,
            entryFundingRate
        );

        uint totalFees = fundingFee + IGmxVault(gmxVault).getPositionFee(size);

        if (totalFees > value) {
            value = 0;
        } else {
            value =
                (value - totalFees) /
                (IGmxVault(gmxVault).PRICE_PRECISION() /
                    Constants.VAULT_PRECISION);
        }
    }

    function _calculateOutstandingRequestValue(
        address vault
    ) internal view returns (uint256) {
        Registry registry = VaultBaseExternal(vault).registry();
        // increasePositionsIndex is incremented everytime an account creates a request, it's never decremented
        // All requests are executed in order so we search backwards and aggregate all value until we find a request that has been executed
        uint increaseRequestIndex = registry
            .gmxConfig()
            .positionRouter()
            .increasePositionsIndex(vault);

        if (increaseRequestIndex == 0) {
            return 0;
        }

        uint256 value = 0;

        for (uint i = increaseRequestIndex; i > 0; i--) {
            bytes32 key = registry.gmxConfig().positionRouter().getRequestKey(
                vault,
                i
            );
            (address account, address inputToken, uint amountIn) = GmxHelpers
                .getIncreasePositionRequestsData(
                    registry.gmxConfig().positionRouter(),
                    key
                );

            if (account == address(0)) {
                break;
            }

            value += registry.accountant().assetValue(inputToken, amountIn);
        }

        return value;
    }
}

