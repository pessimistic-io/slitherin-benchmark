// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {VersionedInitializable} from "./VersionedInitializable.sol";
import {IGuildAddressesProvider} from "./IGuildAddressesProvider.sol";
import {IACLManager} from "./IACLManager.sol";
import {IAssetToken} from "./IAssetToken.sol";
import {ILiabilityToken} from "./ILiabilityToken.sol";
import {GuildLogic} from "./GuildLogic.sol";
import {IGuild} from "./IGuild.sol";
import {GuildStorage} from "./GuildStorage.sol";
import {Errors} from "./Errors.sol";
import {CollateralConfiguration} from "./CollateralConfiguration.sol";
import {DataTypes} from "./DataTypes.sol";
import {PerpetualDebtLogic} from "./PerpetualDebtLogic.sol";
import {CollateralLogic} from "./CollateralLogic.sol";
import {BorrowLogic} from "./BorrowLogic.sol";
import {LiquidationLogic} from "./LiquidationLogic.sol";
import {IERC20} from "./contracts_IERC20.sol";
import {ValidationLogic} from "./ValidationLogic.sol";

//debugging
import "./console.sol";

/**
 * @title Guild contract
 * @author Tazz Labs
 * @notice xxx
 * @dev To be covered by a proxy contract, owned by the PoolAddressesProvider of the specific Guild
 * @dev All admin functions are callable by GuildConfigurator contract defined also in the PoolAddressesProvider
 **/
contract Guild is VersionedInitializable, GuildStorage, IGuild {
    using PerpetualDebtLogic for DataTypes.PerpetualDebtData;

    uint256 public constant GUILD_REVISION = 0x1;
    IGuildAddressesProvider public immutable ADDRESSES_PROVIDER;

    /**
     * @dev Only guild configurator can call functions marked by this modifier.
     **/
    modifier onlyGuildConfigurator() {
        _onlyGuildConfigurator();
        _;
    }

    /**
     * @dev Only guild admin can call functions marked by this modifier.
     **/
    modifier onlyGuildAdmin() {
        _onlyGuildAdmin();
        _;
    }

    function _onlyGuildConfigurator() internal view virtual {
        require(ADDRESSES_PROVIDER.getGuildConfigurator() == msg.sender, Errors.CALLER_NOT_GUILD_CONFIGURATOR);
    }

    function _onlyGuildAdmin() internal view virtual {
        require(
            IACLManager(ADDRESSES_PROVIDER.getACLManager()).isGuildAdmin(msg.sender),
            Errors.CALLER_NOT_GUILD_ADMIN
        );
    }

    /// @dev Mutually exclusive reentrancy protection into the guild to/from a method. This method also prevents entrance
    /// to a function before the guild is initialized. The reentrancy guard is required throughout the contract because
    /// we use external dex interactions for refinancing, minting, burning, liquidation, and collateral valuation.
    modifier lock() {
        require(unlocked, Errors.LOCKED);
        unlocked = false;
        _;
        unlocked = true;
    }

    function getRevision() internal pure virtual override returns (uint256) {
        return GUILD_REVISION;
    }

    /**
     * @dev Constructor.
     * @param provider The address of the GuildAddressesProvider contract
     */
    constructor(IGuildAddressesProvider provider) {
        ADDRESSES_PROVIDER = provider;
    }

    /**
     * @notice Initializes the Guild.
     * @dev Function is invoked by the proxy contract when the Guild contract is created
     * @dev Caching the address of the provider in order to reduce gas consumption on subsequent operations
     * @param provider The address of the provider
     **/
    function initialize(IGuildAddressesProvider provider) external virtual initializer {
        require(provider == ADDRESSES_PROVIDER, Errors.INVALID_ADDRESSES_PROVIDER);
    }

    function refinance() external lock {
        _perpetualDebt.refinance();
    }

    /// @inheritdoc IGuild
    /// @dev initializes the 'unlocked' mutex (Guild locked till initPerpetualDebt called)
    function initPerpetualDebt(
        address assetTokenProxyAddress,
        address liabilityTokenProxyAddress,
        address moneyAddress,
        uint256 duration,
        uint256 notionalPriceLimitMax,
        uint256 notionalPriceLimitMin,
        address dexFactory,
        uint24 dexFee
    ) external virtual onlyGuildConfigurator {
        _perpetualDebt.init(
            assetTokenProxyAddress,
            liabilityTokenProxyAddress,
            moneyAddress,
            duration,
            notionalPriceLimitMax,
            notionalPriceLimitMin,
            dexFactory,
            dexFee
        );

        //Unlock guild after perpetual debt initialization
        unlocked = true;
    }

    function getMoney() external view returns (IERC20) {
        return _perpetualDebt.getMoney();
    }

    function getAsset() external view returns (IAssetToken) {
        return _perpetualDebt.getAsset();
    }

    function getLiability() external view returns (ILiabilityToken) {
        return _perpetualDebt.getLiability();
    }

    function getAPY() external view returns (uint256) {
        return _perpetualDebt.getAPY();
    }

    function getDebtNotionalPrice(address oracle) external view returns (uint256) {
        return _perpetualDebt.getNotionalPrice(oracle);
    }

    function getPerpetualDebt() external view returns (DataTypes.PerpetualDebtData memory) {
        return _perpetualDebt;
    }

    /// @inheritdoc IGuild
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) public virtual override lock {
        CollateralLogic.executeDeposit(
            _collaterals,
            _collateralsList,
            DataTypes.ExecuteDepositParams({asset: asset, amount: amount, onBehalfOf: onBehalfOf})
        );
    }

    /// @inheritdoc IGuild
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) public virtual override lock returns (uint256) {
        return
            CollateralLogic.executeWithdraw(
                _collaterals,
                _collateralsList,
                _perpetualDebt,
                DataTypes.ExecuteWithdrawParams({
                    asset: asset,
                    amount: amount,
                    to: to,
                    collateralsCount: _collateralsCount,
                    oracle: ADDRESSES_PROVIDER.getPriceOracle()
                })
            );
    }

    /// @inheritdoc IGuild
    function initCollateral(address asset) external virtual override lock onlyGuildConfigurator {
        if (
            GuildLogic.executeInitCollateral(
                _collaterals,
                _collateralsList,
                _collateralsCount,
                MAX_NUMBER_COLLATERALS(),
                asset
            )
        ) {
            _collateralsCount++;
        }
    }

    /// @inheritdoc IGuild
    function dropCollateral(address asset) external virtual override lock onlyGuildConfigurator {
        GuildLogic.executeDropCollateral(_collaterals, _collateralsList, asset);
    }

    /// @inheritdoc IGuild
    function setConfiguration(address asset, DataTypes.CollateralConfigurationMap calldata configuration)
        external
        virtual
        override
        lock
        onlyGuildConfigurator
    {
        require(asset != address(0), Errors.ZERO_ADDRESS_NOT_VALID);
        require(_collaterals[asset].id != 0 || _collateralsList[0] == asset, Errors.COLLATERAL_NOT_LISTED);
        _collaterals[asset].configuration = configuration;
    }

    /// @inheritdoc IGuild
    function MAX_NUMBER_COLLATERALS() public view virtual override returns (uint16) {
        return CollateralConfiguration.MAX_COLLATERALS_COUNT;
    }

    /// @inheritdoc IGuild
    function getCollateralConfiguration(address asset)
        external
        view
        virtual
        override
        returns (DataTypes.CollateralConfigurationMap memory)
    {
        return _collaterals[asset].configuration;
    }

    /// @inheritdoc IGuild
    function getCollateralBalanceOf(address user, address asset) external view virtual override returns (uint256) {
        return _collaterals[asset].balances[user];
    }

    /// @inheritdoc IGuild
    function getCollateralTotalBalance(address asset) external view virtual override returns (uint256) {
        return _collaterals[asset].totalBalance;
    }

    /// @inheritdoc IGuild
    function getCollateralsList() external view virtual override returns (address[] memory) {
        uint256 collateralsListCount = _collateralsCount;
        uint256 droppedCollateralsCount = 0;
        address[] memory collateralsList = new address[](collateralsListCount);

        for (uint256 i = 0; i < collateralsListCount; i++) {
            if (_collateralsList[i] != address(0)) {
                collateralsList[i - droppedCollateralsCount] = _collateralsList[i];
            } else {
                droppedCollateralsCount++;
            }
        }

        // Reduces the length of the collaterals array by `droppedCollateralsCount`
        assembly {
            mstore(collateralsList, sub(collateralsListCount, droppedCollateralsCount))
        }
        return collateralsList;
    }

    /// @inheritdoc IGuild
    function getCollateralAddressById(uint16 id) external view returns (address) {
        return _collateralsList[id];
    }

    /// @inheritdoc IGuild
    function borrow(uint256 amount, address onBehalfOf) public virtual override lock {
        BorrowLogic.executeBorrow(
            _collaterals,
            _collateralsList,
            _perpetualDebt,
            DataTypes.ExecuteBorrowParams({
                user: msg.sender,
                onBehalfOf: onBehalfOf,
                amount: amount,
                collateralsCount: _collateralsCount,
                oracle: ADDRESSES_PROVIDER.getPriceOracle()
            })
        );
    }

    /// @inheritdoc IGuild
    function repay(uint256 amount, address onBehalfOf) public virtual override lock returns (uint256) {
        return
            BorrowLogic.executeRepay(
                _perpetualDebt,
                DataTypes.ExecuteRepayParams({onBehalfOf: onBehalfOf, amount: amount})
            );
    }

    /// @inheritdoc IGuild
    function validateBorrow(uint256 amount, address onBehalfOf) external view override {
        ValidationLogic.validateBorrow(
            _collaterals,
            _collateralsList,
            _perpetualDebt,
            DataTypes.ValidateBorrowParams({
                user: onBehalfOf,
                amount: amount, //amount of zToken to borrow
                collateralsCount: _collateralsCount,
                oracle: ADDRESSES_PROVIDER.getPriceOracle()
            })
        );
    }

    /// @inheritdoc IGuild
    function validateRepay(uint256 amount, address onBehalfOf) external view override {
        DataTypes.PerpDebtConfigurationMap memory perpDebtConfigCache = _perpetualDebt.configuration;
        ValidationLogic.validateRepay(perpDebtConfigCache, amount);
    }

    /// @inheritdoc IGuild
    function validateDeposit(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external view override {
        DataTypes.CollateralData storage collateral = _collaterals[asset];
        DataTypes.CollateralConfigurationMap memory collateralConfigCache = collateral.configuration;
        ValidationLogic.validateDeposit(collateralConfigCache, collateral, onBehalfOf, amount);
    }

    /// @inheritdoc IGuild
    function validateWithdraw(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external view override {
        DataTypes.CollateralData storage collateral = _collaterals[asset];
        DataTypes.CollateralConfigurationMap memory collateralConfigCache = collateral.configuration;
        ValidationLogic.validateWithdraw(collateralConfigCache, amount, collateral.balances[onBehalfOf]);
    }

    /// @inheritdoc IGuild
    function setPerpDebtConfiguration(DataTypes.PerpDebtConfigurationMap calldata configuration)
        external
        virtual
        override
        lock
        onlyGuildConfigurator
    {
        _perpetualDebt.configuration = configuration;
    }

    /// @inheritdoc IGuild
    function setPerpDebtNotionalPriceLimits(uint256 priceMax, uint256 priceMin)
        external
        override
        lock
        onlyGuildConfigurator
    {
        _perpetualDebt.updateNotionalPriceLimit(priceMax, priceMin);
    }

    /// @inheritdoc IGuild
    function getPerpDebtConfiguration() external view returns (DataTypes.PerpDebtConfigurationMap memory) {
        return _perpetualDebt.configuration;
    }

    /// @inheritdoc IGuild
    function getUserAccountData(address user)
        external
        view
        virtual
        override
        returns (userAccountDataStruc memory userAccountData)
    {
        userAccountData = GuildLogic.executeGetUserAccountData(
            _collaterals,
            _collateralsList,
            _perpetualDebt,
            DataTypes.CalculateUserAccountDataParams({
                collateralsCount: _collateralsCount,
                user: user,
                oracle: ADDRESSES_PROVIDER.getPriceOracle()
            })
        );
    }

    /// @inheritdoc IGuild
    function liquidationCall(
        address collateralAsset,
        address user,
        uint256 debtNotionalToCover,
        bool receiveCollateral
    ) public virtual override lock {
        LiquidationLogic.executeLiquidationCall(
            _collaterals,
            _collateralsList,
            _perpetualDebt,
            DataTypes.ExecuteLiquidationCallParams({
                collateralsCount: _collateralsCount,
                debtNotionalToCover: debtNotionalToCover,
                collateralAsset: collateralAsset,
                user: user,
                receiveCollateral: receiveCollateral,
                priceOracle: ADDRESSES_PROVIDER.getPriceOracle()
            })
        );
    }
}

