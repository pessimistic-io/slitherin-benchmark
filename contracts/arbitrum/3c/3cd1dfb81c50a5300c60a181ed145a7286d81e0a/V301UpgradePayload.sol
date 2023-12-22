// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolAddressesProvider, IPool, IPoolConfigurator, DataTypes} from "./AaveV3.sol";
import {IProposalGenericExecutor} from "./IProposalGenericExecutor.sol";
import {ConfiguratorInputTypes} from "./ConfiguratorInputTypes.sol";
import {IERC20Detailed} from "./IERC20Detailed.sol";

contract V301UpgradePayload is IProposalGenericExecutor {
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

  constructor(
    IPoolAddressesProvider poolAddressesProvider,
    IPool pool,
    IPoolConfigurator poolConfigurator,
    address collector,
    address incentivesController,
    address newPoolImpl,
    address newPoolConfiguratorImpl,
    address newProtocolDataProvider,
    address newATokenImpl,
    address newVTokenImpl,
    address newSTokenImpl
  ) {
    POOL_ADDRESSES_PROVIDER = poolAddressesProvider;
    POOL = pool;
    POOL_CONFIGURATOR = poolConfigurator;
    COLLECTOR = collector;
    INCENTIVES_CONTROLLER = incentivesController;

    NEW_POOL_IMPL = newPoolImpl;
    NEW_POOL_CONFIGURATOR_IMPL = newPoolConfiguratorImpl;
    NEW_PROTOCOL_DATA_PROVIDER = newProtocolDataProvider;
    NEW_ATOKEN_IMPL = newATokenImpl;
    NEW_VTOKEN_IMPL = newVTokenImpl;
    NEW_STOKEN_IMPL = newSTokenImpl;
  }

  function execute() public {
    POOL_ADDRESSES_PROVIDER.setPoolImpl(NEW_POOL_IMPL);

    POOL_ADDRESSES_PROVIDER.setPoolConfiguratorImpl(NEW_POOL_CONFIGURATOR_IMPL);

    POOL_ADDRESSES_PROVIDER.setPoolDataProvider(NEW_PROTOCOL_DATA_PROVIDER);

    _updateTokens();
  }

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

