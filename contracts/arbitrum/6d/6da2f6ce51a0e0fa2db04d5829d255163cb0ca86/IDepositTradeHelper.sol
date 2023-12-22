// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {ICollateral, IERC20} from "./ICollateral.sol";
import {IAsset, IVault} from "./IVault.sol";
import {ISwapRouter} from "./ISwapRouter.sol";

interface IDepositTradeHelper {
  struct Permit {
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  struct OffChainBalancerParams {
    uint256 amountOutMinimum;
    uint256 deadline;
  }

  struct OffChainTradeParams {
    address positionToken;
    uint256 deadline;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
  }

  event TradeFeePercentChange(uint256 percent);
  event WstethPoolIdChange(bytes32 wstethPoolId);

  function wrapAndDeposit(
    address recipient,
    bytes calldata depositData,
    OffChainBalancerParams calldata balancerParams
  ) external payable;

  function wrapAndDeposit(
    address recipient,
    OffChainBalancerParams calldata balancerParams
  ) external payable;

  function tradeForPosition(
    address recipient,
    uint256 collateralAmount,
    Permit calldata collateralPermit,
    OffChainTradeParams calldata tradeParams
  ) external;

  function tradeForCollateral(
    address recipient,
    uint256 positionAmount,
    Permit calldata positionPermit,
    OffChainTradeParams calldata tradeParams
  ) external;

  function wrapAndDepositAndTrade(
    address recipient,
    bytes calldata depositData,
    OffChainBalancerParams calldata balancerParams,
    Permit calldata collateralPermit,
    OffChainTradeParams calldata tradeParams
  ) external payable;

  function wrapAndDepositAndTrade(
    address recipient,
    OffChainBalancerParams calldata balancerParams,
    Permit calldata collateralPermit,
    OffChainTradeParams calldata tradeParams
  ) external payable;

  function withdrawAndUnwrap(
    address recipient,
    uint256 amount,
    bytes calldata withdrawData,
    Permit calldata collateralPermit,
    OffChainBalancerParams calldata balancerParams
  ) external;

  function withdrawAndUnwrap(
    address recipient,
    uint256 amount,
    Permit calldata collateralPermit,
    OffChainBalancerParams calldata balancerParams
  ) external;

  function setWstethPoolId(bytes32 wstethPoolId) external;

  function setTradeFeePercent(uint256 tradeFeePercent) external;

  function getBaseToken() external view returns (IERC20);

  function getCollateral() external view returns (ICollateral);

  function getSwapRouter() external view returns (ISwapRouter);

  function getWstethVault() external view returns (IVault);

  function getWstethPoolId() external view returns (bytes32);

  function getTradeFeePercent() external view returns (uint256);

  function POOL_FEE_TIER() external view returns (uint24);
}

