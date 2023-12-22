// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IJoeDexLens} from "./IJoeDexLens.sol";

import {IBaseVault} from "./IBaseVault.sol";
import {IStrategy} from "./IStrategy.sol";
import {IVaultFactory} from "./IVaultFactory.sol";

import {IAPTFarm} from "./IAPTFarm.sol";
import {IRewarder} from "./IRewarder.sol";

interface IAPTFarmLens {
    struct VaultData {
        IBaseVault vault;
        IVaultFactory.VaultType vaultType;
        IStrategy strategy;
        IVaultFactory.StrategyType strategyType;
        bool isDepositsPaused;
        bool isInEmergencyMode;
        address lbPair;
        uint256 lbPairBinStep;
        address tokenX;
        address tokenY;
        uint256 tokenXBalance;
        uint256 tokenYBalance;
        uint256 totalSupply;
        uint256 vaultBalanceUSD;
        bool hasFarm;
        FarmData farmData;
    }

    struct FarmData {
        uint256 farmId;
        uint256 joePerSec;
        IRewarder rewarder;
        uint256 aptBalance;
        uint256 aptBalanceUSD;
    }

    struct VaultDataWithUserInfo {
        VaultData vaultData;
        uint256 userBalance;
        uint256 userBalanceUSD;
        FarmDataWithUserInfo farmDataWithUserInfo;
    }

    struct FarmDataWithUserInfo {
        FarmData farmData;
        uint256 userBalance;
        uint256 userBalanceUSD;
        uint256 pendingJoe;
        uint256 pendingBonusToken;
    }

    function vaultFactory() external view returns (IVaultFactory);

    function aptFarm() external view returns (IAPTFarm);

    function dexLens() external view returns (IJoeDexLens);

    function getAllVaults() external view returns (VaultData[] memory vaultsData);

    function getPaginatedVaultsFromType(IVaultFactory.VaultType vaultType, uint256 startId, uint256 pageSize)
        external
        view
        returns (VaultData[] memory vaultsData);

    function getAllVaultsWithFarms() external view returns (VaultData[] memory farmsData);

    function getPaginatedVaultsWithFarms(uint256 startId, uint256 pageSize)
        external
        view
        returns (VaultData[] memory farmsData);

    function getAllVaultsIncludingUserInfo(address user)
        external
        view
        returns (VaultDataWithUserInfo[] memory vaultsDataWithUserInfo);

    function getPaginatedVaultsIncludingUserInfo(
        address user,
        IVaultFactory.VaultType vaultType,
        uint256 startId,
        uint256 pageSize
    ) external view returns (VaultDataWithUserInfo[] memory vaultsDataWithUserInfo);

    function getAllVaultsWithFarmsIncludingUserInfo(address user)
        external
        view
        returns (VaultDataWithUserInfo[] memory farmsDataWithUserInfo);

    function getPaginatedVaultsWithFarmsIncludingUserInfo(address user, uint256 startId, uint256 pageSize)
        external
        view
        returns (VaultDataWithUserInfo[] memory farmsDataWithUserInfo);
}

