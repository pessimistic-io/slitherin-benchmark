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

    /**
     * @notice Each strategy requires a `strategyWorker` address as input enabling:
     * - future upgrades of `strategyWorker` without breaking compatibility.
     * - scalability of Gelato Automation in case of to many strategies managed by 1 Resolver contract.
     *
     * @dev When deploying a new `strategyWorker`, ensure a corresponding Resolver
     * is deployed and Gelato Automation is configured accordingly.
     */
    struct StrategyParams {
        uint256[] buyPercentages;
        Enums.BuyFrequency buyFrequency;
        address strategyWorker;
        address strategyManager;
    }

    struct WhitelistedDepositAsset {
        address assetAddress;
        Enums.AssetTypes assetType;
        address oracleAddress;
        bool isActive;
    }
}

