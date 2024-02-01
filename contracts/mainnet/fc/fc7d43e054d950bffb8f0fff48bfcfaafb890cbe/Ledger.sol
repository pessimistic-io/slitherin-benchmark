// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./ILedger.sol";
import "./IPriceOracleGetter.sol";
import "./IUserData.sol";
import "./GeneralLogic.sol";
import "./CollateralLogic.sol";
import "./ReservePoolLogic.sol";
import "./CollateralPoolLogic.sol";
import "./TradeLogic.sol";
import "./LiquidationLogic.sol";
import "./PositionLogic.sol";
import "./Errors.sol";
import "./DataTypes.sol";
import "./LedgerStorage.sol";

contract Ledger is ILedger, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using CollateralLogic for DataTypes.CollateralData;

    uint256 public constant VERSION = 2;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    bytes32 public constant LIQUIDATE_EXECUTOR = keccak256("LIQUIDATE_EXECUTOR");

    event UpdatedConfigurator(address oldAddress, address newAddress);

    /**
     * @notice Initializes the upgradeable contract
     * @param treasury_ Address where fees are sent to
     * @param configurator_ Configurator
     */
    function initialize(
        address treasury_,
        address configurator_,
        address userData_
    ) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        DataTypes.ProtocolConfig storage config = LedgerStorage.getProtocolConfig();

        config.treasury = treasury_;
        config.configuratorAddress = configurator_;
        config.userData = userData_;
        config.leverageFactor = 5e18;
        config.liquidationRatioMantissa = 0.9e18;
        config.tradeFeeMantissa = 0.01e18;
        config.swapBufferLimitPercentage = 1.1e18;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Setter for configurator address
     * @param configurator_ The new configurator address
     */
    function updateConfigurator(address configurator_) external onlyOperator {
        require(configurator_ != address(0), Errors.INVALID_ZERO_ADDRESS);
        DataTypes.ProtocolConfig storage configuration = LedgerStorage.getProtocolConfig();
        emit UpdatedConfigurator(configuration.configuratorAddress, configurator_);
        configuration.configuratorAddress = configurator_;
    }

    function setProtocolConfig(DataTypes.ProtocolConfig memory config) external onlyConfigurator {
        DataTypes.ProtocolConfig storage configuration = LedgerStorage.getProtocolConfig();
        configuration.treasury = config.treasury;
        configuration.userData = config.userData;
        configuration.leverageFactor = config.leverageFactor;
        configuration.tradeFeeMantissa = config.tradeFeeMantissa;
        configuration.liquidationRatioMantissa = config.liquidationRatioMantissa;
        configuration.swapBufferLimitPercentage = config.swapBufferLimitPercentage;
    }

    function getProtocolConfig() external pure returns (DataTypes.ProtocolConfig memory) {
        return LedgerStorage.getProtocolConfig();
    }

    function whitelistedCallers(address caller) external view returns (bool) {
        return LedgerStorage.getMappingStorage().whitelistedCallers[caller];
    }

    function userLastTradeBlock(address caller) external view returns (uint256) {
        return LedgerStorage.getMappingStorage().userLastTradeBlock[caller];
    }

    function liquidatedCollaterals(address asset) external view returns (uint256) {
        return LedgerStorage.getMappingStorage().liquidatedCollaterals[asset];
    }

    /**
     * @notice Setter for whitelisted addresses
     * @param address_  new whitelisted address
     * @param on_  bool flag for whitelist address
     */
    function setWhitelist(address address_, bool on_) external onlyOperator {
        LedgerStorage.getMappingStorage().whitelistedCallers[address_] = on_;
    }

    /********************** CORE FUNCTIONS *******************************/

    /**
     * @notice Registers an asset to the ledger
     * @param asset Address
     * @return assigned assetId
     */
    function initAssetConfiguration(address asset) external onlyConfigurator returns (uint256) {
        DataTypes.AssetStorage storage assetStorage = LedgerStorage.getAssetStorage();
        assetStorage.assetsCount++;
        assetStorage.assetsList[assetStorage.assetsCount] = asset;
        assetStorage.assetConfigs[asset].assetId = assetStorage.assetsCount;
        return assetStorage.assetsCount;
    }

    /**
     * @notice Configures an asset on the ledger
     * @param asset Address
     * @param configuration configuration
     */
    function setAssetConfiguration(
        address asset,
        DataTypes.AssetConfig memory configuration
    ) public onlyConfigurator {
        require(configuration.assetId == LedgerStorage.getAssetStorage().assetConfigs[asset].assetId, Errors.INVALID_ASSET_CONFIGURATION);
        LedgerStorage.getAssetStorage().assetConfigs[asset] = configuration;
    }

    // TODO: can be moved to a library
    /*
    * @notice Initialize Reserve
    * @param asset initialize asset address
    */
    function initReserve(address asset) external onlyConfigurator returns (uint256) {
        DataTypes.ReserveStorage storage reserveStorage = LedgerStorage.getReserveStorage();

        require(reserveStorage.reservesList[asset] == 0, Errors.POOL_EXIST);

        reserveStorage.reservesCount++;
        uint256 localPid = reserveStorage.reservesCount;

        reserveStorage.reservesList[asset] = localPid;

        reserveStorage.reserves[localPid].poolId = localPid;
        reserveStorage.reserves[localPid].asset = asset;
        reserveStorage.reserves[localPid].reserveIndexRay = MathUtils.RAY;
        reserveStorage.reserves[localPid].lastUpdatedTimestamp = block.timestamp;

        return localPid;
    }

    /*
    * @notice Setter for Reserve Reinvestment
    * @param pid Pool Id
    * @param reinvestment Address where the asset is reinvested in
    */
    function setReserveReinvestment(uint256 pid, address newReinvestment) external onlyConfigurator {
        DataTypes.ReserveData storage reserve = LedgerStorage.getReserveStorage().reserves[pid];
        require(reserve.asset != address(0), Errors.POOL_NOT_INITIALIZED);
        reserve.ext.reinvestment = newReinvestment;
    }

    /*
    * @notice Setter for Reserve Reinvestment
    * @param pid Pool Id
    * @param reinvestment Address where the asset is reinvested in
    */
    function setReserveBonusPool(uint256 pid, address newBonusPool) external onlyConfigurator {
        DataTypes.ReserveData storage reserve = LedgerStorage.getReserveStorage().reserves[pid];
        require(reserve.asset != address(0), Errors.POOL_NOT_INITIALIZED);
        reserve.ext.bonusPool = newBonusPool;
    }

    /*
    * @notice Setter for Reserve Reinvestment
    * @param pid Pool Id
    * @param reinvestment Address where the asset is reinvested in
    */
    function setReserveLongReinvestment(uint256 pid, address newReinvestment) external onlyConfigurator {
        DataTypes.ReserveData storage reserve = LedgerStorage.getReserveStorage().reserves[pid];
        require(reserve.asset != address(0), Errors.POOL_NOT_INITIALIZED);
        reserve.ext.longReinvestment = newReinvestment;
    }

    /*
    * @notice Setter for the Reserve Config
    * @param asset Address
    * @param configuration configuration
    */
    function setReserveConfiguration(uint256 pid, DataTypes.ReserveConfiguration memory configuration) external onlyConfigurator {
        ReservePoolLogic.setReserveConfiguration(pid, configuration);
    }

    /**
     * @notice Initializes a collateral
     * @param asset Address
     * @param reinvestment Address where the asset is reinvested in
     */
    function initCollateral(
        address asset,
        address reinvestment
    ) external onlyConfigurator returns (uint256) {
        DataTypes.CollateralStorage storage collateralStorage = LedgerStorage.getCollateralStorage();
        require(collateralStorage.collateralsList[asset][reinvestment] == 0, Errors.POOL_EXIST);

        collateralStorage.collateralsCount++;
        uint256 localPid = collateralStorage.collateralsCount;
        collateralStorage.collateralsList[asset][reinvestment] = localPid;

        collateralStorage.collaterals[localPid].poolId = localPid;
        collateralStorage.collaterals[localPid].asset = asset;
        collateralStorage.collaterals[localPid].reinvestment = reinvestment;

        return localPid;
    }

    function setCollateralReinvestment(uint256 pid, address newReinvestment) external onlyConfigurator {
        DataTypes.CollateralStorage storage collateralStorage = LedgerStorage.getCollateralStorage();
        DataTypes.CollateralData memory collateral = collateralStorage.collaterals[pid];
        require(collateral.asset != address(0), Errors.POOL_NOT_INITIALIZED);
        collateralStorage.collateralsList[collateral.asset][newReinvestment] = pid;
        delete collateralStorage.collateralsList[collateral.asset][collateral.reinvestment];
        collateralStorage.collaterals[pid].reinvestment = newReinvestment;
    }

    function setCollateralConfiguration(
        uint256 pid,
        DataTypes.CollateralConfiguration memory configuration
    ) public onlyConfigurator {
        require(pid != 0, Errors.POOL_NOT_INITIALIZED);
        LedgerStorage.getCollateralStorage().collaterals[pid].configuration = configuration;
    }

    function depositReserve(address asset, uint256 amount) external nonReentrant onlyWhitelistedCaller {
        ReservePoolLogic.executeDepositReserve(
            msg.sender,
            asset,
            amount
        );
    }

    function withdrawReserve(address asset, uint256 amount) external nonReentrant onlyWhitelistedCaller {
        ReservePoolLogic.executeWithdrawReserve(
            msg.sender,
            asset,
            amount
        );
    }

    function depositCollateral(address asset, address reinvestment, uint256 amount) external nonReentrant onlyWhitelistedCaller {
        CollateralPoolLogic.executeDepositCollateral(
            msg.sender,
            asset,
            reinvestment,
            amount
        );
    }

    function withdrawCollateral(address asset, address reinvestment, uint256 amount) external nonReentrant onlyWhitelistedCaller {
        CollateralPoolLogic.executeWithdrawCollateral(
            msg.sender,
            asset,
            reinvestment,
            amount
        );
    }

    /**
     * @notice Trade
     * @param shortAsset The shorting asset address
     * @param longAsset The longing asset address
     * @param amount The swap amount without fees applied
     * @param data The swap quotes with fees applied
     */
    function trade(address shortAsset, address longAsset, uint256 amount, bytes memory data) external nonReentrant onlyWhitelistedCaller {
        TradeLogic.executeTrade(
            msg.sender,
            shortAsset,
            longAsset,
            amount,
            data
        );
    }

    /**
     * @notice Repay short position
     * @param asset Address
     * @param amount Amount to repay
     */
    function repayShort(address asset, uint256 amount, address behalfOf) external nonReentrant onlyWhitelistedCaller {
        PositionLogic.executeRepayShort(
            msg.sender,
            behalfOf,
            asset,
            amount
        );
    }

    /**
     * @notice Withdraw from long position
     * @param asset Address
     * @param amount Amount to withdraw
     */
    function withdrawLong(address asset, uint256 amount) external nonReentrant onlyWhitelistedCaller {
        PositionLogic.executeWithdrawLong(
            msg.sender,
            asset,
            amount
        );
    }

    function getLibrariesVersion() external pure returns (uint256,uint256,uint256,uint256,uint256,uint256) {
        return (
            GeneralLogic.VERSION,
            ReservePoolLogic.VERSION,
            CollateralPoolLogic.VERSION,
            PositionLogic.VERSION,
            TradeLogic.VERSION,
            LiquidationLogic.VERSION
        );
    }

    /**
     * @notice Get a asset's config
     * @param asset Address
     * @return The asset's config
    */
    function getAssetConfiguration(address asset) external view returns (DataTypes.AssetConfig memory) {
        return LedgerStorage.getAssetStorage().assetConfigs[asset];
    }

    /**
     * @notice Get a reserve data
     * @param asset Address
     * @return The Reserve Data
     */
    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory) {
        return LedgerStorage.getReserveStorage().reserves[
            LedgerStorage.getReserveStorage().reservesList[asset]
        ];
    }

    /**
     * @notice Get a collateral data
     * @param asset Address
     * @param reinvestment Address
     * @return The Collateral Data
    */
    function getCollateralData(address asset, address reinvestment) external view returns (DataTypes.CollateralData memory) {
        return LedgerStorage.getCollateralStorage().collaterals[
            LedgerStorage.getCollateralStorage().collateralsList[asset][reinvestment]
        ];
    }

    /**
     * @notice Get reserve indexes
     * @param asset Address
     * @return reserveIndex reserve index
     * @return protocolIndex protocol index
     * @return borrowIndex borrow index
    */
    function getReserveIndexes(address asset) external override view returns (uint256, uint256, uint256) {
        return ReservePoolLogic.getReserveIndexes(asset);
    }

    /**
     * @notice Get a reserve's list of supply
     * @param asset Address
     * @return availableSupply Available supply
     * @return reserveSupply Reserve supply
     * @return protocolUtilizedSupply Protocol utilized supply
     * @return totalSupply Totality of reserve supply with protocol utilized supply
     * @return utilizedSupply Utilized supply
     */
    function reserveSupplies(address asset) external view returns (uint256, uint256, uint256, uint256, uint256) {
        return ReservePoolLogic.getReserveSupplies(asset);
    }

    /**
     * @notice Get collateral total supply
     * @param asset Address
     * @param reinvestment Address where the asset is reinvested in
     * @return collateral Total supply of the collateral
     */
    function collateralTotalSupply(address asset, address reinvestment) external view returns (uint256) {
        return LedgerStorage.getCollateralStorage().collaterals[
            LedgerStorage.getCollateralStorage().collateralsList[asset][reinvestment]
        ].getCollateralSupply();
    }

    /**
     * @notice Get user's liquidity
     * @param user_ User's address
     * @return userLiquidity User's liquidity
     */
    function getUserLiquidity(address user_) external view returns (
        DataTypes.UserLiquidity memory
    ) {
        // resolve stack too deep
        address user = user_;

        (DataTypes.UserLiquidity memory result,) = GeneralLogic.getUserLiquidity(
            user,
            address(0),
            address(0)
        );

        return result;
    }

    /**
     * @notice CheckpointReserve
     * @param asset Address
     */
    function checkpointReserve(address asset) external {
        ReservePoolLogic.checkpointReserve(asset);
    }

    /**
     * @notice Claim reinvestment rewards from collateral deposits
     * @param asset Underlying asset address
     * @param reinvestment Address where the asset is reinvested in
     */
    function claimCollateralReinvestmentRewards(address asset, address reinvestment) external {
        CollateralPoolLogic.claimReinvestmentRewards(msg.sender, asset, reinvestment);
    }

    /******************************* ADMIN METHODS *******************************/

    /**
     * @notice Manage pools reinvestment
     * @param actionId Action id
     * @param pid Pool Id
     */
    function managePoolReinvestment(uint256 actionId, uint256 pid) external onlyConfigurator {
        if (actionId == 0) {
            ReservePoolLogic.executeEmergencyWithdrawReserve(pid);
        } else if (actionId == 1) {
            ReservePoolLogic.executeReinvestReserveSupply(pid);
        } else if (actionId == 2) {
            CollateralPoolLogic.executeEmergencyWithdrawCollateral(pid);
        } else if (actionId == 3) {
            CollateralPoolLogic.executeReinvestCollateralSupply(pid);
        } else if (actionId == 4) {
            ReservePoolLogic.executeEmergencyWithdrawLong(pid);
        } else if (actionId == 5) {
            ReservePoolLogic.executeReinvestLongSupply(pid);
        } else {
            revert(Errors.INVALID_ACTION_ID);
        }
    }

    /*
     * @notice Sweep reserve long supply profit
     * @param asset Reserve asset
     */
    function sweepLongReinvestment(address asset) external onlyOperator {
        ReservePoolLogic.executeSweepLongReinvestment(asset);
    }

    /**
     * @notice Sweep unregistered assets in Ledger
     * @param otherAsset Asset address
     */
    function sweep(address otherAsset) external onlyOperator {
        require(LedgerStorage.getAssetStorage().assetConfigs[otherAsset].assetId == 0, Errors.CANNOT_SWEEP_REGISTERED_ASSET);
        IERC20Upgradeable(otherAsset).safeTransfer(
            LedgerStorage.getProtocolConfig().treasury,
            IERC20Upgradeable(otherAsset).balanceOf(address(this))
        );
    }

    /******************************* LIQUIDATION METHODS *******************************/

    /**
     * @notice Foreclose a user
     * @param users collection of user addresses to foreclose
     */
    function foreclose(address[] memory users) external onlyLiquidateExecutor {
        LiquidationLogic.executeForeclosure(users);
    }

    /**
     * @notice Unwrapping LP tokens
     * @param unwrapper Address
     * @param asset Address
     * @param amount Amount
     */
    function unwrapLp(address unwrapper, address asset, uint256 amount) external onlyLiquidateExecutor {
        LiquidationLogic.executeUnwrapLp(unwrapper, asset, amount);
    }

    /**
     * @notice Settle liquidation wallet positions
     * @param assetIn Address
     * @param assetOut Address648
     * @param amount Amount
     * @param data Swap Data
     */
    function swapPosition(address assetIn, address assetOut, uint256 amount, bytes memory data) external onlyLiquidateExecutor {
        TradeLogic.liquidationTrade(assetIn, assetOut, amount, data);
    }

    function withdrawLiquidationWalletLong(address asset, uint256 amount) external onlyOperator {
        LiquidationLogic.executeWithdrawLiquidationWalletLong(asset, amount);
    }

    /********************** MODIFIER *******************************/

    modifier onlyConfigurator() {
        require(LedgerStorage.getProtocolConfig().configuratorAddress == msg.sender, Errors.CALLER_NOT_CONFIGURATOR);
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), Errors.CALLER_NOT_OPERATOR);
        _;
    }

    modifier onlyWhitelistedCaller() {
        // it should be from an address || it should be from a whitelisted contract
        require(msg.sender == tx.origin || LedgerStorage.getMappingStorage().whitelistedCallers[msg.sender] == true, Errors.CALLER_NOT_WHITELISTED);
        _;
    }

    modifier onlyLiquidateExecutor() {
        require(hasRole(LIQUIDATE_EXECUTOR, msg.sender), Errors.CALLER_NOT_LIQUIDATE_EXECUTOR);
        _;
    }
}

