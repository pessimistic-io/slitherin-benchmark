// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title   Deposit Assets Whitelister.
 * @author  Pulsar Finance
 * @dev     VERSION: 1.0
 *          DATE:    2023.10.04
 */

import {Enums} from "./Enums.sol";
import {Errors} from "./Errors.sol";
import {ConfigTypes} from "./ConfigTypes.sol";
import {Ownable} from "./Ownable.sol";
import {IStrategyManager} from "./IStrategyManager.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {IPriceFeedsDataConsumer} from "./IPriceFeedsDataConsumer.sol";

contract StrategyManager is IStrategyManager, Ownable {
    uint256 public constant SAFETY_FACTORS_PRECISION_MULTIPLIER = 1000;
    uint256 private _MAX_EXPECTED_GAS_UNITS_WEI = 2_500_000;

    mapping(Enums.BuyFrequency => uint256)
        private _maxNumberOfActionsPerFrequency;

    mapping(Enums.StrategyTimeLimitsInDays => uint256)
        private _gasCostSafetyFactors;

    mapping(Enums.AssetTypes => mapping(Enums.StrategyTimeLimitsInDays => uint256))
        private _depositTokenPriceSafetyFactors;

    mapping(Enums.BuyFrequency => uint256) private _numberOfDaysPerBuyFrequency;

    address[] private _whitelistedDepositAssetAddresses;
    mapping(address => ConfigTypes.WhitelistedDepositAsset)
        private _whitelistedDepositAssets;

    IPriceFeedsDataConsumer public priceFeedsDataConsumer;

    constructor(address _priceFeedsDataConsumer) Ownable(msg.sender) {
        _fillNumberOfDaysPerBuyFrequency();
        _fillMaxNumberOfActionsPerFrequencyDefaultMap();
        _fillGasCostSafetyFactorsDefaultMap();
        _fillDepositTokenPriceSafetyFactorsDefaultMap();
        priceFeedsDataConsumer = IPriceFeedsDataConsumer(
            _priceFeedsDataConsumer
        );
    }

    function addWhitelistedDepositAssets(
        ConfigTypes.WhitelistedDepositAsset[] calldata depositAssetsToWhitelist
    ) external onlyOwner {
        uint256 _assetsLength = depositAssetsToWhitelist.length;
        for (uint256 i; i < _assetsLength; ) {
            if (
                _whitelistedDepositAssets[
                    depositAssetsToWhitelist[i].assetAddress
                ].assetAddress == address(0) /** @dev Avoid duplicates */
            ) {
                _whitelistedDepositAssetAddresses.push(
                    depositAssetsToWhitelist[i].assetAddress
                );
            }
            _whitelistedDepositAssets[
                depositAssetsToWhitelist[i].assetAddress
            ] = depositAssetsToWhitelist[i];
            unchecked {
                ++i;
            }
        }
    }

    function deactivateWhitelistedDepositAsset(
        address depositTokenAddress
    ) external onlyOwner {
        _whitelistedDepositAssets[depositTokenAddress].isActive = false;
    }

    function setMaxExpectedGasUnits(
        uint256 maxExpectedGasUnits
    ) external onlyOwner {
        if (maxExpectedGasUnits <= 0) {
            revert Errors.InvalidParameters(
                "Max expected gas units value must be greater than zero"
            );
        }
        _MAX_EXPECTED_GAS_UNITS_WEI = maxExpectedGasUnits;
    }

    function setGasCostSafetyFactor(
        Enums.StrategyTimeLimitsInDays strategyTimeLimitsInDays,
        uint32 gasCostSafetyFactor
    ) external onlyOwner {
        _gasCostSafetyFactors[strategyTimeLimitsInDays] = gasCostSafetyFactor;
    }

    function setDepositTokenPriceSafetyFactor(
        Enums.AssetTypes assetType,
        Enums.StrategyTimeLimitsInDays strategyTimeLimitsInDays,
        uint32 depositTokenPriceSafetyFactor
    ) external onlyOwner {
        _depositTokenPriceSafetyFactors[assetType][
            strategyTimeLimitsInDays
        ] = depositTokenPriceSafetyFactor;
    }

    function getMaxNumberOfActionsPerFrequency(
        Enums.BuyFrequency buyFrequency
    ) external view returns (uint256) {
        return _maxNumberOfActionsPerFrequency[buyFrequency];
    }

    function getMaxExpectedGasUnits() public view returns (uint256) {
        return _MAX_EXPECTED_GAS_UNITS_WEI;
    }

    /**
        @dev Assets returned can already be deactivated. Check getWhitelistedDepositAsset(address)
    */
    function getWhitelistedDepositAssetAddresses()
        external
        view
        returns (address[] memory)
    {
        return _whitelistedDepositAssetAddresses;
    }

    function getWhitelistedDepositAsset(
        address depositAssetAddress
    ) external view returns (ConfigTypes.WhitelistedDepositAsset memory) {
        return _whitelistedDepositAssets[depositAssetAddress];
    }

    /**
        @dev The `getGasCostSafetyFactor` does not have a `fallback return` in case any of the if conditions 
        are met because it implies that maxNumberOfDays > 365. 
        In this case isMaxNumberOfStrategyActionsValid (previously checked) MUST return false.
        Keep this in mind if you need to modify any of the following mapping parameters hardcoded in this contract:
        - _numberOfDaysPerBuyFrequency
        - _maxNumberOfActionsPerFrequency
    */
    function getGasCostSafetyFactor(
        uint256 maxNumberOfStrategyActions,
        Enums.BuyFrequency buyFrequency
    ) public view returns (uint256) {
        uint256 buyFrequencyInDays = _numberOfDaysPerBuyFrequency[buyFrequency];
        uint256 maxNumberOfDays = buyFrequencyInDays *
            maxNumberOfStrategyActions;
        bool isMaxNumberOfStrategyActionsValidBool = this
            .isMaxNumberOfStrategyActionsValid(
                maxNumberOfStrategyActions,
                buyFrequency
            );
        if (!isMaxNumberOfStrategyActionsValidBool) {
            revert Errors.InvalidParameters(
                "Max number of actions exceeds the limit"
            );
        }
        if (maxNumberOfDays <= 30) {
            return _gasCostSafetyFactors[Enums.StrategyTimeLimitsInDays.THIRTY];
        }
        if (maxNumberOfDays <= 90) {
            return _gasCostSafetyFactors[Enums.StrategyTimeLimitsInDays.NINETY];
        }
        if (maxNumberOfDays <= 180) {
            return
                _gasCostSafetyFactors[
                    Enums.StrategyTimeLimitsInDays.ONE_HUNDRED_AND_EIGHTY
                ];
        }
        if (maxNumberOfDays <= 365) {
            return
                _gasCostSafetyFactors[
                    Enums.StrategyTimeLimitsInDays.THREE_HUNDRED_AND_SIXTY_FIVE
                ];
        }
    }

    /**
        @dev The `getDepositTokenPriceSafetyFactor` does not have a `fallback return` in case any of the if conditions 
        are met because it implies that maxNumberOfDays > 365. 
        In this case isMaxNumberOfStrategyActionsValid (previously checked) MUST return false.
        Keep this in mind if you need to modify any of the following mapping parameters hardcoded in this contract:
        - _numberOfDaysPerBuyFrequency
        - _maxNumberOfActionsPerFrequency
    */
    function getDepositTokenPriceSafetyFactor(
        Enums.AssetTypes assetType,
        uint256 maxNumberOfStrategyActions,
        Enums.BuyFrequency buyFrequency
    ) public view returns (uint256) {
        uint256 buyFrequencyInDays = _numberOfDaysPerBuyFrequency[buyFrequency];
        bool isMaxNumberOfStrategyActionsValidBool = this
            .isMaxNumberOfStrategyActionsValid(
                maxNumberOfStrategyActions,
                buyFrequency
            );
        if (!isMaxNumberOfStrategyActionsValidBool) {
            revert Errors.InvalidParameters(
                "Max number of actions exceeds the limit"
            );
        }
        uint256 maxNumberOfDays = buyFrequencyInDays *
            maxNumberOfStrategyActions;
        if (maxNumberOfDays <= 30) {
            return
                _depositTokenPriceSafetyFactors[assetType][
                    Enums.StrategyTimeLimitsInDays.THIRTY
                ];
        }
        if (maxNumberOfDays <= 90) {
            return
                _depositTokenPriceSafetyFactors[assetType][
                    Enums.StrategyTimeLimitsInDays.NINETY
                ];
        }
        if (maxNumberOfDays <= 180) {
            return
                _depositTokenPriceSafetyFactors[assetType][
                    Enums.StrategyTimeLimitsInDays.ONE_HUNDRED_AND_EIGHTY
                ];
        }
        if (maxNumberOfDays <= 365) {
            return
                _depositTokenPriceSafetyFactors[assetType][
                    Enums.StrategyTimeLimitsInDays.THREE_HUNDRED_AND_SIXTY_FIVE
                ];
        }
    }

    function simulateMinDepositValue(
        ConfigTypes.WhitelistedDepositAsset calldata whitelistedDepositAsset,
        uint256 maxNumberOfStrategyActions,
        Enums.BuyFrequency buyFrequency,
        uint256 treasuryPercentageFeeOnBalanceUpdate,
        uint256 depositAssetDecimals,
        uint256 previousBalance,
        uint256 gasPriceWei
    ) external view returns (uint256 minDepositValue) {
        (
            uint256 nativeTokenPrice,
            uint256 nativeTokenPriceDecimals
        ) = priceFeedsDataConsumer
                .getNativeTokenDataFeedLatestPriceAndDecimals();
        (
            uint256 tokenPrice,
            uint256 tokenPriceDecimals
        ) = priceFeedsDataConsumer.getDataFeedLatestPriceAndDecimals(
                whitelistedDepositAsset.oracleAddress
            );
        // prettier-ignore
        minDepositValue = ((
            nativeTokenPrice 
            * PercentageMath.PERCENTAGE_FACTOR 
            * getMaxExpectedGasUnits() 
            * maxNumberOfStrategyActions 
            * gasPriceWei 
            * getGasCostSafetyFactor(maxNumberOfStrategyActions,buyFrequency) 
            * (10 ** (tokenPriceDecimals + depositAssetDecimals))
        ) / (
            tokenPrice 
            * treasuryPercentageFeeOnBalanceUpdate 
            * getDepositTokenPriceSafetyFactor(whitelistedDepositAsset.assetType, maxNumberOfStrategyActions,buyFrequency)
            * (10 ** (18 + nativeTokenPriceDecimals))
        ));
        minDepositValue = minDepositValue > previousBalance
            ? minDepositValue - previousBalance
            : 0;
    }

    function isMaxNumberOfStrategyActionsValid(
        uint256 maxNumberOfStrategyActions,
        Enums.BuyFrequency buyFrequency
    ) external view returns (bool) {
        uint256 buyFrequencyInDays = _numberOfDaysPerBuyFrequency[buyFrequency];
        uint256 maxNumberOfDays = buyFrequencyInDays *
            maxNumberOfStrategyActions;
        uint256 maxNumberOfDaysAllowed = _maxNumberOfActionsPerFrequency[
            buyFrequency
        ] * buyFrequencyInDays;
        return maxNumberOfDays <= maxNumberOfDaysAllowed;
    }

    function _fillNumberOfDaysPerBuyFrequency() private {
        _numberOfDaysPerBuyFrequency[Enums.BuyFrequency.DAILY] = 1;
        _numberOfDaysPerBuyFrequency[Enums.BuyFrequency.WEEKLY] = 7;
        _numberOfDaysPerBuyFrequency[Enums.BuyFrequency.BI_WEEKLY] = 14;
        _numberOfDaysPerBuyFrequency[Enums.BuyFrequency.MONTHLY] = 30;
    }

    function _fillMaxNumberOfActionsPerFrequencyDefaultMap() private {
        _maxNumberOfActionsPerFrequency[Enums.BuyFrequency.DAILY] = 60;
        _maxNumberOfActionsPerFrequency[Enums.BuyFrequency.WEEKLY] = 52;
        _maxNumberOfActionsPerFrequency[Enums.BuyFrequency.BI_WEEKLY] = 26;
        _maxNumberOfActionsPerFrequency[Enums.BuyFrequency.MONTHLY] = 12;
    }

    function _fillGasCostSafetyFactorsDefaultMap() private {
        _gasCostSafetyFactors[Enums.StrategyTimeLimitsInDays.THIRTY] = 1000;
        _gasCostSafetyFactors[Enums.StrategyTimeLimitsInDays.NINETY] = 2250;
        _gasCostSafetyFactors[
            Enums.StrategyTimeLimitsInDays.ONE_HUNDRED_AND_EIGHTY
        ] = 3060;
        _gasCostSafetyFactors[
            Enums.StrategyTimeLimitsInDays.THREE_HUNDRED_AND_SIXTY_FIVE
        ] = 4000;
    }

    function _fillDepositTokenPriceSafetyFactorsDefaultMap() private {
        _depositTokenPriceSafetyFactors[Enums.AssetTypes.STABLE][
            Enums.StrategyTimeLimitsInDays.THIRTY
        ] = 1000;
        _depositTokenPriceSafetyFactors[Enums.AssetTypes.STABLE][
            Enums.StrategyTimeLimitsInDays.NINETY
        ] = 1000;
        _depositTokenPriceSafetyFactors[Enums.AssetTypes.STABLE][
            Enums.StrategyTimeLimitsInDays.ONE_HUNDRED_AND_EIGHTY
        ] = 1000;
        _depositTokenPriceSafetyFactors[Enums.AssetTypes.STABLE][
            Enums.StrategyTimeLimitsInDays.THREE_HUNDRED_AND_SIXTY_FIVE
        ] = 1000;
        _depositTokenPriceSafetyFactors[Enums.AssetTypes.ETH_BTC][
            Enums.StrategyTimeLimitsInDays.THIRTY
        ] = 1000;
        _depositTokenPriceSafetyFactors[Enums.AssetTypes.ETH_BTC][
            Enums.StrategyTimeLimitsInDays.NINETY
        ] = 1000;
        _depositTokenPriceSafetyFactors[Enums.AssetTypes.ETH_BTC][
            Enums.StrategyTimeLimitsInDays.ONE_HUNDRED_AND_EIGHTY
        ] = 1000;
        _depositTokenPriceSafetyFactors[Enums.AssetTypes.ETH_BTC][
            Enums.StrategyTimeLimitsInDays.THREE_HUNDRED_AND_SIXTY_FIVE
        ] = 1000;
        _depositTokenPriceSafetyFactors[Enums.AssetTypes.BLUE_CHIP][
            Enums.StrategyTimeLimitsInDays.THIRTY
        ] = 900;
        _depositTokenPriceSafetyFactors[Enums.AssetTypes.BLUE_CHIP][
            Enums.StrategyTimeLimitsInDays.NINETY
        ] = 800;
        _depositTokenPriceSafetyFactors[Enums.AssetTypes.BLUE_CHIP][
            Enums.StrategyTimeLimitsInDays.ONE_HUNDRED_AND_EIGHTY
        ] = 650;
        _depositTokenPriceSafetyFactors[Enums.AssetTypes.BLUE_CHIP][
            Enums.StrategyTimeLimitsInDays.THREE_HUNDRED_AND_SIXTY_FIVE
        ] = 500;
    }
}

