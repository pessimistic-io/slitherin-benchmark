// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import {DataTypes} from "./DataTypes.sol";
import {ConfiguratorInputTypes} from "./ConfiguratorInputTypes.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {IPool} from "./IPool.sol";
import {IPoolConfigurator} from "./IPoolConfigurator.sol";
import {IPriceOracleGetter} from "./IPriceOracleGetter.sol";
import {IAaveOracle} from "./IAaveOracle.sol";
import {IACLManager as BasicIACLManager} from "./IACLManager.sol";
import {IPoolDataProvider} from "./IPoolDataProvider.sol";
import {IDefaultInterestRateStrategy} from "./IDefaultInterestRateStrategy.sol";
import {IReserveInterestRateStrategy} from "./IReserveInterestRateStrategy.sol";
import {IPoolDataProvider as IAaveProtocolDataProvider} from "./IPoolDataProvider.sol";

/**
 * @title ICollector
 * @notice Defines the interface of the Collector contract
 * @author Aave
 **/
interface ICollector {
  /**
   * @dev Emitted during the transfer of ownership of the funds administrator address
   * @param fundsAdmin The new funds administrator address
   **/
  event NewFundsAdmin(address indexed fundsAdmin);

  /**
   * @dev Retrieve the current implementation Revision of the proxy
   * @return The revision version
   */
  function REVISION() external view returns (uint256);

  /**
   * @dev Retrieve the current funds administrator
   * @return The address of the funds administrator
   */
  function getFundsAdmin() external view returns (address);

  /**
   * @dev Approve an amount of tokens to be pulled by the recipient.
   * @param token The address of the asset
   * @param recipient The address of the entity allowed to pull tokens
   * @param amount The amount allowed to be pulled. If zero it will revoke the approval.
   */
  function approve(
    // IERC20 token,
    address token,
    address recipient,
    uint256 amount
  ) external;

  /**
   * @dev Transfer an amount of tokens to the recipient.
   * @param token The address of the asset
   * @param recipient The address of the entity to transfer the tokens.
   * @param amount The amount to be transferred.
   */
  function transfer(
    // IERC20 token,
    address token,
    address recipient,
    uint256 amount
  ) external;

  /**
   * @dev Transfer the ownership of the funds administrator role.
          This function should only be callable by the current funds administrator.
   * @param admin The address of the new funds administrator
   */
  function setFundsAdmin(address admin) external;
}

interface IACLManager is BasicIACLManager {
  function hasRole(bytes32 role, address account) external view returns (bool);

  function DEFAULT_ADMIN_ROLE() external pure returns (bytes32);

  function renounceRole(bytes32 role, address account) external;
}

