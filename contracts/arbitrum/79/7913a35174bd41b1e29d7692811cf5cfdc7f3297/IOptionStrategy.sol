// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;

import {IRouter} from "./IRouter.sol";
import {IOption} from "./IOption.sol";
import {ISwap} from "./ISwap.sol";

interface IOptionStrategy {
    // One deposit can buy from different providers
    struct OptionParams {
        // Swap Data (WETH -> token needed to buy options)
        // Worst case we make 4 swaps
        bytes swapData;
        // Swappper to buy options (default: OneInch)
        ISwap swapper;
        // Amount of lp to BULL
        uint256 percentageLpBull;
    }

    struct Strike {
        // Strike price, eg: $1800
        uint256 price;
        // How much it cost to buy one option for the given strike
        uint256 costIndividual;
        // How much it was spent in total for this strike
        uint256 costTotal;
        // From the amount set to be spent on options, how much this strike represents of the total portion
        uint256 percentageOverTotalCollateral;
        // Current amount of options
        uint256 currentOptions;
    }

    // Index 0 is most profitable option
    struct ExecuteStrategy {
        uint256 currentEpoch;
        // Array of providers
        IOption[] providers;
        // amount of the broken lp that will go to the provider to purchase options
        uint256[] providerPercentage;
        // Each provider can have different strikes
        // Strikes according to the same order as percentageEachStrike. Using 8 decimals
        uint256[][] strikes;
        uint256[][] collateralEachStrike;
        // Used for Dopex's leave blank (0) for other providers.
        uint256[] expiry;
        // Extra data for options providers
        bytes[] externalData;
    }

    // Struct used to collect profits from options purchase
    struct CollectRewards {
        // System epoch
        uint256 currentEpoch;
        // Array of providers
        IOption[] providers;
        // Extra data for options providers
        bytes[] externalData;
    }

    // Deposits into OptionStrategy to execute options logic
    struct Budget {
        // Deposits to buy options
        uint128 totalDeposits;
        uint128 bullDeposits;
        uint128 bearDeposits;
        // Profits from options
        uint128 bullEarned;
        uint128 bearEarned;
        uint128 totalEarned;
    }

    struct DifferenceAndOverpaying {
        // Strike (eg: 1800e8)
        uint256 strikePrice;
        // How much it costs to buy strike
        uint256 strikeCost;
        // Amount of collateral going to given strike
        uint256 collateral;
        // ToFarm -> only in case options prices are now cheaper
        uint256 toFarm;
        // true -> means options prices are now higher than when strategy was executed
        // If its false, we are purchasing same amount of options with less collateral and sending extra to farm
        bool isOverpaying;
    }

    function deposit(uint256 _epoch, uint256 _amount, uint256 _bullDeposits, uint256 _bearDeposits) external;
    function middleEpochOptionsBuy(
        uint256 _epoch,
        IRouter.OptionStrategy _type,
        IOption _provider,
        uint256 _collateralAmount,
        uint256 _strike
    ) external returns (uint256);
    function afterMiddleEpochOptionsBuy(IRouter.OptionStrategy _type, uint256 _collateralAmount) external;
    function optionPosition(uint256 _epoch, IRouter.OptionStrategy _type) external view returns (uint256);
    function deltaPrice(uint256 _epoch, uint256 usersAmountOfLp, IOption _provider)
        external
        view
        returns (DifferenceAndOverpaying[] memory);
    function dopexAdapter(IOption.OPTION_TYPE) external view returns (IOption);
    function startCrabStrategy(IRouter.OptionStrategy _strategyType, uint256 _epoch) external;
    function getBullProviders(uint256 epoch) external view returns (IOption[] memory);
    function getBearProviders(uint256 epoch) external view returns (IOption[] memory);
    function executeBullStrategy(uint256 _epoch, uint128 _toSpend, ExecuteStrategy calldata _execute) external;
    function executeBearStrategy(uint256 _epoch, uint128 _toSpend, ExecuteStrategy calldata _execute) external;
    function collectRewards(IOption.OPTION_TYPE _type, CollectRewards calldata _collect, bytes memory _externalData)
        external
        returns (uint256);
    function getBoughtStrikes(uint256 _epoch, IOption _provider) external view returns (Strike[] memory);
    function addBoughtStrikes(uint256 _epoch, IOption _provider, Strike memory _data) external;
    function updateOptionStrike(uint256 _epoch, IOption _provider, uint256 _strike, Strike memory _data) external;
    function settleOptionStrike(uint256 _epoch, IOption _provider, uint256 _strike) external;
    function borrowedLP(IRouter.OptionStrategy _type) external view returns (uint256);
    function executedStrategy(uint256 _epoch, IRouter.OptionStrategy _type) external view returns (bool);
}

