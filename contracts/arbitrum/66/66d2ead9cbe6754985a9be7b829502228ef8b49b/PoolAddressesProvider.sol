// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {Ownable} from "./Ownable.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {     ITransparentAdminUpgradeableProxy,     TransparentAdminUpgradeableProxy } from "./TransparentAdminUpgradeableProxy.sol";

/**
 * @title PoolAddressesProvider
 *
 * @notice Main registry of addresses part of or connected to the protocol, including permissioned roles
 * @dev Acts as factory of proxies and admin of those, so with right to change its implementations
 * @dev Owned by the YLDR Governance
 */
contract PoolAddressesProvider is Ownable, IPoolAddressesProvider {
    // Identifier of the YLDR Market
    string private _marketId;

    // Map of registered addresses (identifier => registeredAddress)
    mapping(bytes32 => address) private _addresses;

    // Main identifiers
    bytes32 private constant POOL = "POOL";
    bytes32 private constant POOL_CONFIGURATOR = "POOL_CONFIGURATOR";
    bytes32 private constant PRICE_ORACLE = "PRICE_ORACLE";
    bytes32 private constant ACL_MANAGER = "ACL_MANAGER";
    bytes32 private constant ACL_ADMIN = "ACL_ADMIN";
    bytes32 private constant PRICE_ORACLE_SENTINEL = "PRICE_ORACLE_SENTINEL";
    bytes32 private constant DATA_PROVIDER = "DATA_PROVIDER";

    /**
     * @dev Constructor.
     * @param marketId The identifier of the market.
     * @param owner The owner address of this contract.
     */
    constructor(string memory marketId, address owner) Ownable(owner) {
        _setMarketId(marketId);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getMarketId() external view override returns (string memory) {
        return _marketId;
    }

    /// @inheritdoc IPoolAddressesProvider
    function setMarketId(string memory newMarketId) external override onlyOwner {
        _setMarketId(newMarketId);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getAddress(bytes32 id) public view override returns (address) {
        return _addresses[id];
    }

    /// @inheritdoc IPoolAddressesProvider
    function setAddress(bytes32 id, address newAddress) external override onlyOwner {
        address oldAddress = _addresses[id];
        _addresses[id] = newAddress;
        emit AddressSet(id, oldAddress, newAddress);
    }

    /// @inheritdoc IPoolAddressesProvider
    function setAddressAsProxy(bytes32 id, address newImplementationAddress) external override onlyOwner {
        address proxyAddress = _addresses[id];
        _updateImpl(id, newImplementationAddress);
        emit AddressSetAsProxy(id, proxyAddress, newImplementationAddress);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getPool() external view override returns (address) {
        return getAddress(POOL);
    }

    /// @inheritdoc IPoolAddressesProvider
    function setPoolImpl(address newPoolImpl) external override onlyOwner {
        _updateImpl(POOL, newPoolImpl);
        emit PoolUpdated(newPoolImpl);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getPoolConfigurator() external view override returns (address) {
        return getAddress(POOL_CONFIGURATOR);
    }

    /// @inheritdoc IPoolAddressesProvider
    function setPoolConfiguratorImpl(address newPoolConfiguratorImpl) external override onlyOwner {
        _updateImpl(POOL_CONFIGURATOR, newPoolConfiguratorImpl);
        emit PoolConfiguratorUpdated(newPoolConfiguratorImpl);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getPriceOracle() external view override returns (address) {
        return getAddress(PRICE_ORACLE);
    }

    /// @inheritdoc IPoolAddressesProvider
    function setPriceOracle(address newPriceOracle) external override onlyOwner {
        address oldPriceOracle = _addresses[PRICE_ORACLE];
        _addresses[PRICE_ORACLE] = newPriceOracle;
        emit PriceOracleUpdated(oldPriceOracle, newPriceOracle);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getACLManager() external view override returns (address) {
        return getAddress(ACL_MANAGER);
    }

    /// @inheritdoc IPoolAddressesProvider
    function setACLManager(address newAclManager) external override onlyOwner {
        address oldAclManager = _addresses[ACL_MANAGER];
        _addresses[ACL_MANAGER] = newAclManager;
        emit ACLManagerUpdated(oldAclManager, newAclManager);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getACLAdmin() external view override returns (address) {
        return getAddress(ACL_ADMIN);
    }

    /// @inheritdoc IPoolAddressesProvider
    function setACLAdmin(address newAclAdmin) external override onlyOwner {
        address oldAclAdmin = _addresses[ACL_ADMIN];
        _addresses[ACL_ADMIN] = newAclAdmin;
        emit ACLAdminUpdated(oldAclAdmin, newAclAdmin);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getPriceOracleSentinel() external view override returns (address) {
        return getAddress(PRICE_ORACLE_SENTINEL);
    }

    /// @inheritdoc IPoolAddressesProvider
    function setPriceOracleSentinel(address newPriceOracleSentinel) external override onlyOwner {
        address oldPriceOracleSentinel = _addresses[PRICE_ORACLE_SENTINEL];
        _addresses[PRICE_ORACLE_SENTINEL] = newPriceOracleSentinel;
        emit PriceOracleSentinelUpdated(oldPriceOracleSentinel, newPriceOracleSentinel);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getPoolDataProvider() external view override returns (address) {
        return getAddress(DATA_PROVIDER);
    }

    /// @inheritdoc IPoolAddressesProvider
    function setPoolDataProvider(address newDataProvider) external override onlyOwner {
        address oldDataProvider = _addresses[DATA_PROVIDER];
        _addresses[DATA_PROVIDER] = newDataProvider;
        emit PoolDataProviderUpdated(oldDataProvider, newDataProvider);
    }

    /**
     * @notice Internal function to update the implementation of a specific proxied component of the protocol.
     * @dev If there is no proxy registered with the given identifier, it creates the proxy setting `newAddress`
     *   as implementation and calls the initialize() function on the proxy
     * @dev If there is already a proxy registered, it just updates the implementation to `newAddress` and
     *   calls the initialize() function via upgradeToAndCall() in the proxy
     * @param id The id of the proxy to be updated
     * @param newAddress The address of the new implementation
     */
    function _updateImpl(bytes32 id, address newAddress) internal {
        address proxyAddress = _addresses[id];
        bytes memory params = abi.encodeWithSignature("initialize(address)", address(this));

        if (proxyAddress == address(0)) {
            TransparentAdminUpgradeableProxy proxy =
                new TransparentAdminUpgradeableProxy(newAddress, address(this), params);
            _addresses[id] = proxyAddress = address(proxy);
            emit ProxyCreated(id, proxyAddress, newAddress);
        } else {
            ITransparentAdminUpgradeableProxy(proxyAddress).upgradeToAndCall(newAddress, params);
        }
    }

    /**
     * @notice Updates the identifier of the YLDR market.
     * @param newMarketId The new id of the market
     */
    function _setMarketId(string memory newMarketId) internal {
        string memory oldMarketId = _marketId;
        _marketId = newMarketId;
        emit MarketIdSet(oldMarketId, newMarketId);
    }
}

