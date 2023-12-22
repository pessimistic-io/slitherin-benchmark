// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Enums} from "./Enums.sol";
import {ConfigTypes} from "./ConfigTypes.sol";

interface IStrategyManager {
    function addWhitelistedDepositAssets(
        ConfigTypes.WhitelistedDepositAsset[] calldata depositAssetsToWhitelist
    ) external;

    function deactivateWhitelistedDepositAsset(
        address depositTokenAddress
    ) external;

    function setMaxExpectedGasUnits(uint256 maxExpectedGasUnits) external;

    function setGasCostSafetyFactor(
        Enums.StrategyTimeLimitsInDays strategyTimeLimitsInDays,
        uint32 gasCostSafetyFactor
    ) external;

    function setDepositTokenPriceSafetyFactor(
        Enums.AssetTypes assetType,
        Enums.StrategyTimeLimitsInDays strategyTimeLimitsInDays,
        uint32 depositTokenPriceSafetyFactor
    ) external;

    function getMaxNumberOfActionsPerFrequency(
        Enums.BuyFrequency buyFrequency
    ) external view returns (uint256);

    function getWhitelistedDepositAssetAddresses()
        external
        view
        returns (address[] memory);

    function getWhitelistedDepositAsset(
        address depositAssetAddress
    ) external view returns (ConfigTypes.WhitelistedDepositAsset memory);

    function simulateMinDepositValue(
        ConfigTypes.WhitelistedDepositAsset calldata whitelistedDepositAsset,
        uint256 maxNumberOfStrategyActions,
        Enums.BuyFrequency buyFrequency,
        uint256 treasuryPercentageFeeOnBalanceUpdate,
        uint256 depositAssetDecimals,
        uint256 previousBalance,
        uint256 gasPriceWei
    ) external view returns (uint256 minDepositValue);
}

