// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import {DataTypes} from "./DataTypes.sol";
import {Errors} from "./Errors.sol";
import {ConfiguratorInputTypes} from "./ConfiguratorInputTypes.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {IAToken} from "./IAToken.sol";
import {IPool} from "./IPool.sol";
import {IPoolConfigurator} from "./IPoolConfigurator.sol";
import {IPriceOracleGetter} from "./IPriceOracleGetter.sol";
import {IAaveOracle} from "./IAaveOracle.sol";
import {IACLManager as BasicIACLManager} from "./IACLManager.sol";
import {IPoolDataProvider} from "./IPoolDataProvider.sol";
import {IDefaultInterestRateStrategy} from "./IDefaultInterestRateStrategy.sol";
import {IReserveInterestRateStrategy} from "./IReserveInterestRateStrategy.sol";
import {IPoolDataProvider as IAaveProtocolDataProvider} from "./IPoolDataProvider.sol";
import {AggregatorInterface} from "./common_AggregatorInterface.sol";

interface IACLManager is BasicIACLManager {
  function hasRole(bytes32 role, address account) external view returns (bool);

  function DEFAULT_ADMIN_ROLE() external pure returns (bytes32);

  function renounceRole(bytes32 role, address account) external;

  function getRoleAdmin(bytes32 role) external view returns (bytes32);

  function grantRole(bytes32 role, address account) external;

  function revokeRole(bytes32 role, address account) external;
}

