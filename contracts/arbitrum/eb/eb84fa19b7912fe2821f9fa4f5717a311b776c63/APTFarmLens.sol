// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IERC20Metadata} from "./IERC20Metadata.sol";
import {ILBPair} from "./ILBPair.sol";

import {     IAPTFarmLens,     IVaultFactory,     IBaseVault,     IStrategy,     IAPTFarm,     IRewarder,     IJoeDexLens } from "./IAPTFarmLens.sol";

contract APTFarmLens is IAPTFarmLens {
    /**
     * @notice The vault factory contract
     */
    IVaultFactory public immutable override vaultFactory;

    /**
     * @notice The APT farm contract
     */
    IAPTFarm public immutable override aptFarm;

    /**
     * @notice The Joe Dex Lens contract
     */
    IJoeDexLens public immutable override dexLens;

    constructor(IVaultFactory _vaultFactory, IAPTFarm _aptFarm, IJoeDexLens _dexLens) {
        vaultFactory = _vaultFactory;
        aptFarm = _aptFarm;
        dexLens = _dexLens;
    }

    /**
     * @notice Returns data for every vault created by the vault factory
     * @return vaultsData The vault data array for every vault created by the vault factory
     */
    function getAllVaults() external view override returns (VaultData[] memory vaultsData) {
        vaultsData = _getAllVaults();
    }

    /**
     * @notice Returns paginated data for every vault created by the vault factory
     * @param vaultType The vault type
     * @param startId The start id
     * @param pageSize The amount of vaults to get
     * @return vaultsData The vault data array for every vault created by the vault factory
     */
    function getPaginatedVaultsFromType(IVaultFactory.VaultType vaultType, uint256 startId, uint256 pageSize)
        external
        view
        override
        returns (VaultData[] memory vaultsData)
    {
        vaultsData = _getVaults(vaultType, startId, pageSize);
    }

    /**
     * @notice Returns data for every vault that has a farm
     * @return farmsData The vault data array for every vault that has a farm
     */
    function getAllVaultsWithFarms() external view override returns (VaultData[] memory farmsData) {
        farmsData = _getAllVaultsWithFarms();
    }

    /**
     * @notice Returns paginated data for every vault that has a farm
     * @param startId The start id
     * @param pageSize The amount of vaults to get
     * @return farmsData The vault data array for every vault that has a farm
     */
    function getPaginatedVaultsWithFarms(uint256 startId, uint256 pageSize)
        external
        view
        override
        returns (VaultData[] memory farmsData)
    {
        farmsData = _getVaultsWithFarms(startId, pageSize);
    }

    /**
     * @notice Returns data for every vault created by the vault factory with the user's info
     * @param user The user's address
     * @return vaultsDataWithUserInfo The vault data array with the user's info
     */
    function getAllVaultsIncludingUserInfo(address user)
        external
        view
        override
        returns (VaultDataWithUserInfo[] memory vaultsDataWithUserInfo)
    {
        VaultData[] memory vaultsData = _getAllVaults();

        vaultsDataWithUserInfo = new VaultDataWithUserInfo[](vaultsData.length);

        for (uint256 i = 0; i < vaultsData.length; i++) {
            vaultsDataWithUserInfo[i] = _getVaultUserInfo(vaultsData[i], user);
        }
    }
    /**
     * @notice Returns paginated data for every vault created by the vault factory with the user's info
     * @param user The user's address
     * @param vaultType The vault type
     * @param startId The start id
     * @param pageSize The amount of vaults to get
     * @return vaultsDataWithUserInfo The vault data array with the user's info
     */

    function getPaginatedVaultsIncludingUserInfo(
        address user,
        IVaultFactory.VaultType vaultType,
        uint256 startId,
        uint256 pageSize
    ) external view override returns (VaultDataWithUserInfo[] memory vaultsDataWithUserInfo) {
        VaultData[] memory vaultsData = _getVaults(vaultType, startId, pageSize);

        vaultsDataWithUserInfo = new VaultDataWithUserInfo[](vaultsData.length);

        for (uint256 i = 0; i < vaultsData.length; i++) {
            vaultsDataWithUserInfo[i] = _getVaultUserInfo(vaultsData[i], user);
        }
    }

    /**
     * @notice Returns data for every vault that has a farm, with the user's info
     * @param user The user's address
     * @return farmsDataWithUserInfo The vault data array with the user's info
     */
    function getAllVaultsWithFarmsIncludingUserInfo(address user)
        external
        view
        override
        returns (VaultDataWithUserInfo[] memory farmsDataWithUserInfo)
    {
        VaultData[] memory farmsData = _getAllVaultsWithFarms();

        farmsDataWithUserInfo = new VaultDataWithUserInfo[](farmsData.length);

        for (uint256 i = 0; i < farmsData.length; i++) {
            farmsDataWithUserInfo[i] = _getVaultUserInfo(farmsData[i], user);
        }
    }

    /**
     * @notice Returns paginated data for every vault that has a farm, with the user's info
     * @param user The user's address
     * @param startId The start id
     * @param pageSize The amount of vaults to get
     * @return farmsDataWithUserInfo The vault data array with the user's info
     */
    function getPaginatedVaultsWithFarmsIncludingUserInfo(address user, uint256 startId, uint256 pageSize)
        external
        view
        override
        returns (VaultDataWithUserInfo[] memory farmsDataWithUserInfo)
    {
        VaultData[] memory farmsData = _getVaultsWithFarms(startId, pageSize);

        farmsDataWithUserInfo = new VaultDataWithUserInfo[](farmsData.length);

        for (uint256 i = 0; i < farmsData.length; i++) {
            farmsDataWithUserInfo[i] = _getVaultUserInfo(farmsData[i], user);
        }
    }

    /**
     * @dev Gets all the vaults created by the vault factory
     * @return vaultsData The vault data array
     */
    function _getAllVaults() internal view returns (VaultData[] memory vaultsData) {
        uint256 totalOracleVaults = vaultFactory.getNumberOfVaults(IVaultFactory.VaultType.Oracle);
        uint256 totalSimpleVaults = vaultFactory.getNumberOfVaults(IVaultFactory.VaultType.Simple);

        vaultsData = new VaultData[](totalOracleVaults + totalSimpleVaults);

        for (uint256 i = 0; i < totalOracleVaults; i++) {
            vaultsData[i] = _getVaultAt(IVaultFactory.VaultType.Oracle, i);
        }

        for (uint256 i = 0; i < totalSimpleVaults; i++) {
            vaultsData[totalOracleVaults + i] = _getVaultAt(IVaultFactory.VaultType.Simple, i);
        }
    }

    /**
     * @dev Gets all the vaults from the specified type created by the vault factory
     * @param vaultType The vault type
     * @param startId The start id
     * @param pageSize The amount of vaults to get
     * @return vaultsData The vault data array
     */
    function _getVaults(IVaultFactory.VaultType vaultType, uint256 startId, uint256 pageSize)
        internal
        view
        returns (VaultData[] memory vaultsData)
    {
        uint256 totalSimpleVaults = vaultFactory.getNumberOfVaults(vaultType);

        if (startId >= totalSimpleVaults) {
            return vaultsData;
        }

        if (startId + pageSize > totalSimpleVaults) {
            pageSize = totalSimpleVaults - startId;
        }

        vaultsData = new VaultData[](pageSize);

        for (uint256 i = 0; i < pageSize; i++) {
            vaultsData[i] = _getVaultAt(vaultType, startId + i);
        }
    }

    /**
     * @dev Gets all the vault of the specified type created at the specified index
     * @param vaultType The vault type
     * @param vaultId The vault id
     * @return vaultData The vault data
     */
    function _getVaultAt(IVaultFactory.VaultType vaultType, uint256 vaultId)
        internal
        view
        returns (VaultData memory vaultData)
    {
        IBaseVault vault = IBaseVault(vaultFactory.getVaultAt(vaultType, vaultId));
        vaultData = _getVault(vault, vaultType);
    }

    /**
     * @dev Gets the vault information
     * @param vault The vault address
     * @return vaultData The vault data
     */
    function _getVault(IBaseVault vault) internal view returns (VaultData memory vaultData) {
        IVaultFactory.VaultType vaultType = vaultFactory.getVaultType(address(vault));

        vaultData = _getVault(vault, vaultType);
    }

    /**
     * @dev Gets the vault information, considering that we already know the vault type
     * @param vault The vault address
     * @param vaultType The vault type
     * @return vaultData The vault data
     */
    function _getVault(IBaseVault vault, IVaultFactory.VaultType vaultType)
        internal
        view
        returns (VaultData memory vaultData)
    {
        FarmData memory farmInfo;
        if (aptFarm.hasFarm(address(vault))) {
            uint256 farmId = aptFarm.vaultFarmId(address(vault));
            farmInfo = _getFarm(farmId);
        }

        address tokenX = address(vault.getTokenX());
        address tokenY = address(vault.getTokenY());

        (uint256 tokenXBalance, uint256 tokenYBalance) = vault.getBalances();

        IStrategy strategy = vault.getStrategy();
        ILBPair lbPair = vault.getPair();

        vaultData = VaultData({
            vault: vault,
            vaultType: vaultType,
            strategy: strategy,
            strategyType: vaultFactory.getStrategyType(address(strategy)),
            isDepositsPaused: vault.isDepositsPaused(),
            isInEmergencyMode: address(strategy) == address(0) && (tokenXBalance > 0 || tokenYBalance > 0),
            lbPair: address(lbPair),
            lbPairBinStep: lbPair.getBinStep(),
            tokenX: tokenX,
            tokenY: tokenY,
            tokenXBalance: tokenXBalance,
            tokenYBalance: tokenYBalance,
            totalSupply: vault.totalSupply(),
            vaultBalanceUSD: _getVaultTokenUSDValue(vault, vault.totalSupply()),
            hasFarm: aptFarm.hasFarm(address(vault)),
            farmData: farmInfo
        });
    }

    /**
     * @dev Appends the user's info to the vault data
     * @param vaultData The vault data
     * @param user The user's address
     * @return vaultDataWithUserInfo The vault data with the user's info
     */
    function _getVaultUserInfo(VaultData memory vaultData, address user)
        internal
        view
        returns (VaultDataWithUserInfo memory vaultDataWithUserInfo)
    {
        uint256 userBalance = vaultData.vault.balanceOf(user);
        uint256 userBalanceUSD =
            vaultData.totalSupply == 0 ? 0 : vaultData.vaultBalanceUSD * userBalance / vaultData.totalSupply;

        FarmDataWithUserInfo memory farmDataWithUserInfo;

        if (vaultData.hasFarm) {
            farmDataWithUserInfo = _getFarmUserInfo(vaultData.farmData, user);
        }

        vaultDataWithUserInfo = VaultDataWithUserInfo({
            vaultData: vaultData,
            userBalance: userBalance,
            userBalanceUSD: userBalanceUSD,
            farmDataWithUserInfo: farmDataWithUserInfo
        });
    }

    /**
     * @dev Gets the farm data for every vault that has a farm
     * @return farmsData The farm data array
     */
    function _getAllVaultsWithFarms() internal view returns (VaultData[] memory farmsData) {
        farmsData = _getVaultsWithFarms(0, type(uint256).max);
    }

    /**
     * @dev Gets the paginated farm data for every vault that has a farm
     * @param startId The start id
     * @param pageSize The amount of farms to get
     * @return farmsData The farm data array
     */
    function _getVaultsWithFarms(uint256 startId, uint256 pageSize)
        internal
        view
        returns (VaultData[] memory farmsData)
    {
        uint256 totalFarms = aptFarm.farmLength();

        if (startId >= totalFarms) {
            return farmsData;
        }

        if (startId + pageSize > totalFarms) {
            pageSize = totalFarms - startId;
        }

        farmsData = new VaultData[](pageSize);

        for (uint256 i = 0; i < pageSize; i++) {
            IBaseVault vault = IBaseVault(address(aptFarm.farmInfo(startId + i).apToken));

            farmsData[i] = _getVault(vault);
        }
    }

    /**
     * @dev Gets the farm information for the specified farm
     * @param farmId The farm id
     * @return farmData The farm data
     */
    function _getFarm(uint256 farmId) internal view returns (FarmData memory farmData) {
        IAPTFarm.FarmInfo memory farmInfo = aptFarm.farmInfo(farmId);

        IBaseVault vault = IBaseVault(address(farmInfo.apToken));

        farmData = FarmData({
            farmId: farmId,
            joePerSec: farmInfo.joePerSec,
            rewarder: IRewarder(farmInfo.rewarder),
            aptBalance: farmInfo.apToken.balanceOf(address(aptFarm)),
            aptBalanceUSD: _getVaultTokenUSDValue(vault, farmInfo.apToken.balanceOf(address(aptFarm)))
        });
    }

    /**
     * @dev Appends the user's info to the farm data
     * @param farmData The farm data
     * @param user The user's address
     * @return farmDataWithUserInfo The farm data with the user's info
     */
    function _getFarmUserInfo(FarmData memory farmData, address user)
        internal
        view
        returns (FarmDataWithUserInfo memory farmDataWithUserInfo)
    {
        uint256 userBalance = aptFarm.userInfo(farmData.farmId, user).amount;
        uint256 userBalanceUSD =
            farmData.aptBalance == 0 ? 0 : farmData.aptBalanceUSD * userBalance / farmData.aptBalance;

        (uint256 pendingJoe,,, uint256 pendingBonusToken) = aptFarm.pendingTokens(farmData.farmId, user);

        farmDataWithUserInfo = FarmDataWithUserInfo({
            farmData: farmData,
            userBalance: userBalance,
            userBalanceUSD: userBalanceUSD,
            pendingJoe: pendingJoe,
            pendingBonusToken: pendingBonusToken
        });
    }

    /**
     * @dev Gets the vault token USD value
     * @param vault The vault address
     * @param amount The amount of vault tokens
     * @return tokenUSDValue The vault token USD value
     */
    function _getVaultTokenUSDValue(IBaseVault vault, uint256 amount) internal view returns (uint256 tokenUSDValue) {
        (address tokenX, address tokenY) = (address(vault.getTokenX()), address(vault.getTokenY()));
        (uint256 amountX, uint256 amountY) = vault.previewAmounts(amount);

        (uint256 tokenXPrice, uint256 tokenYPrice) =
            (dexLens.getTokenPriceUSD(tokenX), dexLens.getTokenPriceUSD(tokenY));

        tokenUSDValue = (amountX * tokenXPrice / (10 ** IERC20Metadata(tokenX).decimals()))
            + (amountY * tokenYPrice / (10 ** IERC20Metadata(tokenY).decimals()));
    }
}

