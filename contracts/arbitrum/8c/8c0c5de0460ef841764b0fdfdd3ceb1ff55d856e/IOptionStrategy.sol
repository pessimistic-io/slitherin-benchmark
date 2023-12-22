// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;

import {IRouter} from "./IRouter.sol";
import {IOption} from "./IOption.sol";
import {ISwap} from "./ISwap.sol";

interface IOptionStrategy {
    // Idea is to one deposit can buy from different providers
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
        uint256 price;
        uint256 costIndividual;
        uint256 costTotal;
        uint256 percentageOverTotalCollateral;
    }

    // Index 0 is most profitable option
    struct ExecuteStrategy {
        uint256 currentEpoch;
        // Array of providers
        IOption[] providers;
        // amount of the broken lp that will go to the provider to purchase options
        uint256[] providerPercentage;
        // Each provider can have different strikes
        uint256[][] strikes; // Strikes according to the same order as percentageEachStrike. Using 8 decimals
        uint256[][] collateralEachStrike;
        uint256[] expiry; // Used for Dopex's leave blank (0) for other providers.
        bytes[] externalData; // Extra data for options providers
    }

    struct CollectRewards {
        uint256 currentEpoch;
        // Array of providers
        IOption[] providers;
        // Each provider can have different strikes
        uint256[][] strikes; // Strikes according to the same order as percentageEachStrike. Using 8 decimals
        bytes[] externalData; // Extra data for options providers
    }

    struct Budget {
        uint128 totalDeposits;
        uint128 bullDeposits;
        uint128 bearDeposits;
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

    // Deposit LP
    function deposit(uint256 _epoch, uint256 _amount, uint256 _bullDeposits, uint256 _bearDeposits) external;

    function middleEpochOptionsBuy(
        uint256 _epoch,
        IRouter.OptionStrategy _type,
        IOption _provider,
        uint256 _collateralAmount,
        uint256 _strike
    ) external returns (uint256);

    // Return current option position plus unused balance in LP tokens
    function optionPosition(uint256 _epoch, IRouter.OptionStrategy _type) external view returns (uint256);

    // Return the % of difference in price than epoch price.
    // if output > BASIS means current price is upper than epoch price
    // if output < BASIS means current price is lower than epoch price
    function deltaPrice(uint256 _epoch, uint256 usersAmountOfLp, IOption _provider)
        external
        view
        returns (DifferenceAndOverpaying[] memory);
    function dopexAdapter(IOption.OPTION_TYPE) external view returns (IOption);
    function startCrabStrategy(IRouter.OptionStrategy _strategyType, uint256 _epoch) external;
    function getBullProviders(uint256 epoch) external view returns (IOption[] memory);
    function getBearProviders(uint256 epoch) external view returns (IOption[] memory);
    function executeBullStrategy(uint256 _epoch, uint128 _toSpend, ExecuteStrategy calldata _execute)
        external;
    function executeBearStrategy(uint256 _epoch, uint128 _toSpend, ExecuteStrategy calldata _execute)
        external;
    function collectRewards(
        IOption.OPTION_TYPE _type,
        CollectRewards calldata _collect,
        bytes memory _externalData
    ) external returns (uint256);
    function getBoughtStrikes(uint256 _epoch, IOption _provider) external view returns (Strike[] memory);
    function addBoughtStrikes(uint256 _epoch, IOption _provider, Strike memory _data) external;
    function borrowedLP(IRouter.OptionStrategy _type) external view returns (uint256);
    function executedStrategy(uint256 _epoch, IRouter.OptionStrategy _type) external view returns (bool);
}

