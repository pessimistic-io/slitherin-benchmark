// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Enums} from "./Enums.sol";
import {IERC20} from "./ERC20.sol";

library ConfigTypes {
    struct InitMultiAssetVaultParams {
        string name;
        string symbol;
        address payable treasury;
        address payable creator;
        address factory;
        bool isActive;
        IERC20 depositAsset;
        IERC20[] buyAssets;
        uint256 creatorPercentageFeeOnDeposit;
        uint256 treasuryPercentageFeeOnBalanceUpdate;
    }
    struct InitMultiAssetVaultFactoryParams {
        string name;
        string symbol;
        address depositAsset;
        address[] buyAssets;
    }
    struct StrategyParams {
        uint256[] buyAmounts;
        Enums.BuyFrequency buyFrequency;
        Enums.StrategyType strategyType;
        address strategyWorker;
    }
}

