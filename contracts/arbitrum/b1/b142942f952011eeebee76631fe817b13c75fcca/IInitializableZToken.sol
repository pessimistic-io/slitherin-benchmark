// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {ILendingPool} from "./ILendingPool.sol";
import {IZarbanIncentivesController} from "./IZarbanIncentivesController.sol";

/**
 * @title IInitializableZToken
 * @notice Interface for the initialize function on ZToken
 * @author Zarban
 **/
interface IInitializableZToken {
  /**
   * @dev Emitted when an zToken is initialized
   * @param underlyingAsset The address of the underlying asset
   * @param pool The address of the associated lending pool
   * @param treasury The address of the treasury
   * @param incentivesController The address of the incentives controller for this zToken
   * @param zTokenDecimals the decimals of the underlying
   * @param zTokenName the name of the zToken
   * @param zTokenSymbol the symbol of the zToken
   * @param params A set of encoded parameters for additional initialization
   **/
  event Initialized(
    address indexed underlyingAsset,
    address indexed pool,
    address treasury,
    address incentivesController,
    uint8 zTokenDecimals,
    string zTokenName,
    string zTokenSymbol,
    bytes params
  );

  /**
   * @dev Initializes the zToken
   * @param pool The address of the lending pool where this zToken will be used
   * @param treasury The address of the Zarban treasury, receiving the fees on this zToken
   * @param underlyingAsset The address of the underlying asset of this zToken (E.g. WETH for zWETH)
   * @param incentivesController The smart contract managing potential incentives distribution
   * @param zTokenDecimals The decimals of the zToken, same as the underlying asset's
   * @param zTokenName The name of the zToken
   * @param zTokenSymbol The symbol of the zToken
   */
  function initialize(
    ILendingPool pool,
    address treasury,
    address underlyingAsset,
    IZarbanIncentivesController incentivesController,
    uint8 zTokenDecimals,
    string calldata zTokenName,
    string calldata zTokenSymbol,
    bytes calldata params
  ) external;
}

