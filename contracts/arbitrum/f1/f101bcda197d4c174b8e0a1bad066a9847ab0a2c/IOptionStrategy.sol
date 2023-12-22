// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;

import {IRouter} from "./IRouter.sol";
import {IOption} from "./IOption.sol";
import {ISwap} from "./ISwap.sol";

interface IOptionStrategy {
    struct Option {
        IRouter.OptionStrategy type_;
        uint32 strike; // ETH/USDC
        uint64 expiry;
        uint256 amount;
        uint256 cost;
    }

    // Index 0 is most profitable option
    struct ExecuteStrategy {
        uint16 epoch;
        IOption[] providers;
        // amount of the broken lp that will go to the provider to purchase options
        uint256[] providerPercentage;
        IOption.OptionParams[] params;
    }

    // Struct used to collect profits from options purchase
    struct CollectRewards {
        // System epoch
        uint16 epoch;
        // Strategy Type
        IRouter.OptionStrategy type_;
        // Array of providers
        address provider;
        // Extra data for options providers
        bytes[] optionData;
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

    struct OptionOverpayAndData {
        // Option strike
        uint32 strike;
        // Amount of options
        uint256 amount;
        // Cost of option strike
        uint256 cost;
        // Option Data
        bytes optionData;
        // Percentaje of collateral used to buy options
        uint256 collateralPercentage;
        // Amount of collateral going to given strike
        uint256 toBuyOptions;
        // ToFarm -> only in case options prices are now cheaper
        uint256 toFarm;
        // true -> means options prices are now higher than when strategy was executed
        // If its false, we are purchasing same amount of options with less collateral and sending extra to farm
        bool isOverpaying;
    }

    function deposit(uint16 _epoch, uint256 _amount, uint256 _bullDeposits, uint256 _bearDeposits) external;
    function middleEpochOptionsBuy(IOption _provider, uint256 _lpAmount, IOption.OptionParams calldata _params)
        external;
    function executeBullStrategy(uint128 _toSpend, ExecuteStrategy calldata _execute, ISwap.SwapInfo calldata _swapInfo)
        external;
    function executeBearStrategy(uint128 _toSpend, ExecuteStrategy calldata _execute, ISwap.SwapInfo calldata _swapInfo)
        external;
    function startCrabStrategy(IRouter.OptionStrategy _strategyType, uint16 _epoch) external;
    function collectRewards(CollectRewards calldata _collect) external;
    function realizeRewards(uint16 _epoch, IRouter.OptionStrategy _type, ISwap.SwapInfo calldata _swapInfo)
        external
        returns (uint256);

    function afterSettleOptions(IRouter.OptionStrategy _type, uint256 _wethAmount) external;

    function afterMiddleEpochOptionsBuy(IRouter.OptionStrategy _type, uint256 _collateralAmount) external;
    function addBoughtStrikes(uint16 _epoch, IRouter.OptionStrategy _type, Option calldata _option) external;

    function getOptions(uint16 _epoch, address _provider, IRouter.OptionStrategy _type)
        external
        view
        returns (Option[] memory);
    function optionPosition(uint16 _epoch, IRouter.OptionStrategy _type) external view returns (uint256);
    function compareStrikes(uint256 _costPaid, uint256 _currentCost, uint256 _baseAmount)
        external
        view
        returns (uint256 toBuyOptions, uint256 toFarm, bool isOverpaying);
    function deltaPrice(
        uint16 _epoch,
        uint256 _userAmountOfLp,
        IRouter.OptionStrategy _strategy,
        bytes calldata _optionOrder,
        address _provider
    ) external view returns (OptionOverpayAndData memory);
    function getBullProviders(uint16 epoch) external view returns (IOption[] memory);
    function getBearProviders(uint16 epoch) external view returns (IOption[] memory);
    function getBudget(uint16 _epoch) external view returns (Budget memory);
    function defaultAdapter(IRouter.OptionStrategy) external view returns (IOption);

    function borrowedLP(IRouter.OptionStrategy _type) external view returns (uint256);
    function executedStrategy(uint16 _epoch, IRouter.OptionStrategy _type) external view returns (bool);

    function swapper() external view returns (ISwap);
}

