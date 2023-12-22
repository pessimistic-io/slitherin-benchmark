// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolAddressesProvider, IPool, IPoolConfigurator, DataTypes, IACLManager} from "./AaveV3.sol";
import {IProposalGenericExecutor} from "./IProposalGenericExecutor.sol";
import {ConfiguratorInputTypes} from "./ConfiguratorInputTypes.sol";
import {IERC20Detailed} from "./IERC20Detailed.sol";

/**
 * @title V301EthereumUpgradePayload
 * @notice Contract for ethereum upgrade from v3.0.0 to v3.0.1
 * - upgrades the pool implementation
 * - adds migrator & swapCollateralAdapter as ISOLATED_COLLATERAL_SUPPLIER
 * @author BGD labs
 */
contract V301EthereumUpgradePayload is IProposalGenericExecutor {
  IPoolAddressesProvider public immutable POOL_ADDRESSES_PROVIDER;
  IPoolConfigurator public immutable POOL_CONFIGURATOR;
  address public immutable NEW_POOL_IMPL;
  IACLManager public immutable ACL_MANAGER;
  address immutable SWAP_COLLATERAL_ADAPTER;
  address immutable MIGRATION_HELPER;

  bytes32 public constant ISOLATED_COLLATERAL_SUPPLIER_ROLE =
    keccak256('ISOLATED_COLLATERAL_SUPPLIER');

  constructor(
    IPoolAddressesProvider poolAddressesProvider,
    IPoolConfigurator poolConfigurator,
    address newPoolImpl,
    IACLManager aclManager,
    address swapCollateralAdapter,
    address migrationHelper
  ) {
    POOL_ADDRESSES_PROVIDER = poolAddressesProvider;
    POOL_CONFIGURATOR = poolConfigurator;
    NEW_POOL_IMPL = newPoolImpl;
    ACL_MANAGER = aclManager;
    SWAP_COLLATERAL_ADAPTER = swapCollateralAdapter;
    MIGRATION_HELPER = migrationHelper;
  }

  function execute() public {
    POOL_ADDRESSES_PROVIDER.setPoolImpl(NEW_POOL_IMPL);
    POOL_CONFIGURATOR.updateFlashloanPremiumTotal(0.0005e4);
    POOL_CONFIGURATOR.updateFlashloanPremiumToProtocol(0.0004e4);
    ACL_MANAGER.grantRole(ISOLATED_COLLATERAL_SUPPLIER_ROLE, SWAP_COLLATERAL_ADAPTER);
    ACL_MANAGER.grantRole(ISOLATED_COLLATERAL_SUPPLIER_ROLE, MIGRATION_HELPER);
  }
}

/**
 * @title V301L2UpgradePayload
 * @notice Base contract for l2s upgrade from v3.0.0 to v3.0.1
 * - upgrades the pool implementation
 * - upgrades the pool configurator implementation
 * - links new PoolDataProvider
 * - upgrades all a/s/v token implementations for all reserves
 * - sets reserveFlashLoaning to true for all reserves
 * @notice this contract is intended to be used on harmony upgrade
 * @author BGD labs
 */
contract V301L2UpgradePayload is IProposalGenericExecutor {
  struct AddressArgs {
    IPoolAddressesProvider poolAddressesProvider;
    IPool pool;
    IPoolConfigurator poolConfigurator;
    address collector;
    address incentivesController;
    address newPoolImpl;
    address newPoolConfiguratorImpl;
    address newProtocolDataProvider;
    address newATokenImpl;
    address newVTokenImpl;
    address newSTokenImpl;
  }

  IPoolAddressesProvider public immutable POOL_ADDRESSES_PROVIDER;
  IPool public immutable POOL;
  IPoolConfigurator public immutable POOL_CONFIGURATOR;
  address public immutable COLLECTOR;
  address public immutable INCENTIVES_CONTROLLER;

  address public immutable NEW_POOL_IMPL;
  address public immutable NEW_POOL_CONFIGURATOR_IMPL;
  address public immutable NEW_PROTOCOL_DATA_PROVIDER;
  address public immutable NEW_ATOKEN_IMPL;
  address public immutable NEW_VTOKEN_IMPL;
  address public immutable NEW_STOKEN_IMPL;

  constructor(AddressArgs memory addresses) {
    POOL_ADDRESSES_PROVIDER = addresses.poolAddressesProvider;
    POOL = addresses.pool;
    POOL_CONFIGURATOR = addresses.poolConfigurator;
    COLLECTOR = addresses.collector;
    INCENTIVES_CONTROLLER = addresses.incentivesController;

    NEW_POOL_IMPL = addresses.newPoolImpl;
    NEW_POOL_CONFIGURATOR_IMPL = addresses.newPoolConfiguratorImpl;
    NEW_PROTOCOL_DATA_PROVIDER = addresses.newProtocolDataProvider;
    NEW_ATOKEN_IMPL = addresses.newATokenImpl;
    NEW_VTOKEN_IMPL = addresses.newVTokenImpl;
    NEW_STOKEN_IMPL = addresses.newSTokenImpl;
  }

  function execute() public {
    POOL_ADDRESSES_PROVIDER.setPoolImpl(NEW_POOL_IMPL);
    POOL_CONFIGURATOR.updateFlashloanPremiumTotal(0.0005e4);
    POOL_CONFIGURATOR.updateFlashloanPremiumToProtocol(0.0004e4);

    POOL_ADDRESSES_PROVIDER.setPoolConfiguratorImpl(NEW_POOL_CONFIGURATOR_IMPL);

    POOL_ADDRESSES_PROVIDER.setPoolDataProvider(NEW_PROTOCOL_DATA_PROVIDER);

    _updateTokens();

    _postExecute();
  }

  function _postExecute() internal virtual {}

  function _updateTokens() internal {
    address[] memory reserves = POOL.getReservesList();

    for (uint256 i = 0; i < reserves.length; i++) {
      DataTypes.ReserveData memory reserveData = POOL.getReserveData(reserves[i]);

      IERC20Detailed aToken = IERC20Detailed(reserveData.aTokenAddress);
      ConfiguratorInputTypes.UpdateATokenInput memory inputAToken = ConfiguratorInputTypes
        .UpdateATokenInput({
          asset: reserves[i],
          treasury: COLLECTOR,
          incentivesController: INCENTIVES_CONTROLLER,
          name: aToken.name(),
          symbol: aToken.symbol(),
          implementation: NEW_ATOKEN_IMPL,
          params: '0x10' // this parameter is not actually used anywhere
        });

      POOL_CONFIGURATOR.updateAToken(inputAToken);

      IERC20Detailed vToken = IERC20Detailed(reserveData.variableDebtTokenAddress);
      ConfiguratorInputTypes.UpdateDebtTokenInput memory inputVToken = ConfiguratorInputTypes
        .UpdateDebtTokenInput({
          asset: reserves[i],
          incentivesController: INCENTIVES_CONTROLLER,
          name: vToken.name(),
          symbol: vToken.symbol(),
          implementation: NEW_VTOKEN_IMPL,
          params: '0x10' // this parameter is not actually used anywhere
        });

      POOL_CONFIGURATOR.updateVariableDebtToken(inputVToken);

      IERC20Detailed sToken = IERC20Detailed(reserveData.stableDebtTokenAddress);
      ConfiguratorInputTypes.UpdateDebtTokenInput memory inputSToken = ConfiguratorInputTypes
        .UpdateDebtTokenInput({
          asset: reserves[i],
          incentivesController: INCENTIVES_CONTROLLER,
          name: sToken.name(),
          symbol: sToken.symbol(),
          implementation: NEW_STOKEN_IMPL,
          params: '0x10' // this parameter is not actually used anywhere
        });

      POOL_CONFIGURATOR.updateStableDebtToken(inputSToken);

      POOL_CONFIGURATOR.setReserveFlashLoaning(reserves[i], true);
    }
  }
}

/**
 * @title SwapPermissionsPayload
 * @notice extends V301L2UpgradePayload
 * - grants ISOLATED_COLLATERAL_SUPPLIER_ROLE to SWAP_COLLATERAL_ADAPTER
 * @notice this contract is intended to be used on optimism/arbitrum/fantom upgrade
 * @author BGD labs
 */
contract SwapPermissionsPayload is V301L2UpgradePayload {
  IACLManager public immutable ACL_MANAGER;
  address immutable SWAP_COLLATERAL_ADAPTER;

  bytes32 public constant ISOLATED_COLLATERAL_SUPPLIER_ROLE =
    keccak256('ISOLATED_COLLATERAL_SUPPLIER');

  constructor(
    AddressArgs memory addresses,
    IACLManager aclManager,
    address swapCollateralAdapter
  ) V301L2UpgradePayload(addresses) {
    ACL_MANAGER = aclManager;
    SWAP_COLLATERAL_ADAPTER = swapCollateralAdapter;
  }

  function _postExecute() internal virtual override {
    ACL_MANAGER.grantRole(ISOLATED_COLLATERAL_SUPPLIER_ROLE, SWAP_COLLATERAL_ADAPTER);
  }
}

/**
 * @title SwapMigratorPermissionsPayload
 * @notice extends SwapPermissionsPayload
 * - grants ISOLATED_COLLATERAL_SUPPLIER_ROLE to MIGRATION_HELPER
 * @notice this contract is intended to be used on polygon/avalanche upgrade
 * @author BGD labs
 */
contract SwapMigratorPermissionsPayload is SwapPermissionsPayload {
  address immutable MIGRATION_HELPER;

  constructor(
    AddressArgs memory addresses,
    IACLManager aclManager,
    address swapCollateralAdapter,
    address migrationHelper
  ) SwapPermissionsPayload(addresses, aclManager, swapCollateralAdapter) {
    MIGRATION_HELPER = migrationHelper;
  }

  function _postExecute() internal override {
    super._postExecute();
    ACL_MANAGER.grantRole(ISOLATED_COLLATERAL_SUPPLIER_ROLE, MIGRATION_HELPER);
  }
}

