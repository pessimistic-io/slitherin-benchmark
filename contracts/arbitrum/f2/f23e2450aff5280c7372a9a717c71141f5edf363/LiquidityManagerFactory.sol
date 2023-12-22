// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {IAlgebraFactory} from "./IAlgebraFactory.sol";

import {IERC20Metadata} from "./IERC20Metadata.sol";
import {Ownable} from "./Ownable.sol";
import {Constants} from "./Constants.sol";
import {LiquidityManager} from "./LiquidityManager.sol";
import "./ILiquidityManagerFactory.sol";

/// @title LiquidityManagerFactory
/// @notice Factory contract for LiquidityManager V1.0
contract LiquidityManagerFactory is Ownable {
  /*****************************************************************/
  /******************            EVENTS           ******************/
  /*****************************************************************/

  event LiquidityManagerCreated(
    address token0,
    address token1,
    address liquidityManager,
    uint256 index
  );

  /*****************************************************************/
  /******************          CONSTANTS         ******************/
  /*****************************************************************/

  address internal immutable POOL_DEPLOYER;
  address internal immutable SWAP_ROUTER;
  IAlgebraFactory internal immutable ALGEBRA_FACTORY;

  /*****************************************************************/
  /******************           STORAGE           ******************/
  /*****************************************************************/

  address[] public allLiquidityManagers;

  /*****************************************************************/
  /******************         CONSTRUCTOR         ******************/
  /*****************************************************************/

  constructor(address _algebraFactory, address _swapRouter, address _poolDeployer) {
    require(_algebraFactory != address(0) && _swapRouter != address(0) && _poolDeployer != address(0), "0");
    ALGEBRA_FACTORY = IAlgebraFactory(_algebraFactory);
    POOL_DEPLOYER = _poolDeployer;
    SWAP_ROUTER = _swapRouter;
  }

  /********************************************************************/
  /****************** EXTERNAL ADMIN-ONLY FUNCTIONS  ******************/
  /********************************************************************/

  /// @notice Create a LiquidityManager
  /// @param token0 Address of token0
  /// @param token1 Address of token1
  /// @param name Name of the liquidity manager
  /// @param symbol Symbol of the liquidityManager
  /// @param feeRecipient Address of the fee recipient
  /// @return liquidityManager Address of liquidityManager created
  function createLiquidityManager(address token0, address token1, string memory name,
    string memory symbol, address feeRecipient) external onlyOwner returns (address liquidityManager)
  {
    require(token0 != token1 && token0 != address(0) && token1 != address(0) && feeRecipient != address(0), "T");
    (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

    address pool = ALGEBRA_FACTORY.poolByPair(token0, token1);
    if (pool == address(0)) {
      pool = ALGEBRA_FACTORY.createPool(token0, token1);
    }
    require(pool != address(0), "P");

    string memory token0Symbol = IERC20Metadata(token0).symbol();
    string memory token1Symbol = IERC20Metadata(token1).symbol();
    liquidityManager = _createLiquidityManager(pool, token0, token1, feeRecipient,
      string(abi.encodePacked(token0Symbol, "/", token1Symbol, "-", name)),
      string(abi.encodePacked(token0Symbol, "/", token1Symbol, "-", symbol))
    );

    require(liquidityManager != address(0), "LM0");

    allLiquidityManagers.push(liquidityManager);
    emit LiquidityManagerCreated(token0, token1, liquidityManager, allLiquidityManagers.length - 1);
  }

  function _createLiquidityManager(address pool, address token0, address token1, address feeRecipient,
    string memory name, string memory symbol) internal virtual returns (address liquidityManager)
  {
    liquidityManager = address(
      new LiquidityManager{salt : keccak256(abi.encodePacked(token0, token1, symbol))}(
        pool, token0, token1, feeRecipient, name, symbol, POOL_DEPLOYER, SWAP_ROUTER
      )
    );
  }

  /********************************************************************/
  /******************       EXTERNAL FUNCTIONS       ******************/
  /********************************************************************/

  function allLiquidityManagersLength() external view returns (uint256) {
    return allLiquidityManagers.length;
  }
}

