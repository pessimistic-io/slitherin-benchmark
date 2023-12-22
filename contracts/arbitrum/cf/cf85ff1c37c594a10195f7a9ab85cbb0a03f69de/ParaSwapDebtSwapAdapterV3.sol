// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./Test.sol";
import {ParaSwapDebtSwapAdapter} from "./ParaSwapDebtSwapAdapter.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {IParaSwapAugustusRegistry} from "./IParaSwapAugustusRegistry.sol";
import {IPool} from "./IPool.sol";
import {DataTypes} from "./DataTypes.sol";

/**
 * @title ParaSwapDebtSwapAdapter
 * @notice ParaSwap Adapter to perform a swap of debt to another debt.
 * @author BGD labs
 **/
contract ParaSwapDebtSwapAdapterV3 is ParaSwapDebtSwapAdapter {
  constructor(
    IPoolAddressesProvider addressesProvider,
    address pool,
    IParaSwapAugustusRegistry augustusRegistry,
    address owner
  ) ParaSwapDebtSwapAdapter(addressesProvider, pool, augustusRegistry, owner) {}

  function _getReserveData(address asset) internal view override returns (address, address) {
    DataTypes.ReserveData memory reserveData = POOL.getReserveData(asset);
    return (reserveData.variableDebtTokenAddress, reserveData.stableDebtTokenAddress);
  }
}

