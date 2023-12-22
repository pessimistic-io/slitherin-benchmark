// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./ICollateral.sol";
import "./IPrePOMarket.sol";
import "./IVault.sol";
import "./ISwapRouter.sol";

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
    address tokenOut;
    uint256 deadline;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
  }

  event WstethPoolIdChange(bytes32 wstethPoolId);

  function wrapAndDeposit(
    address recipient,
    OffChainBalancerParams calldata balancerParams
  ) external payable returns (uint256);

  function depositAndTrade(
    uint256 baseTokenAmount,
    Permit calldata baseTokenPermit,
    Permit calldata collateralPermit,
    OffChainTradeParams calldata tradeParams
  ) external;

  function wrapAndDepositAndTrade(
    Permit calldata collateralPermit,
    OffChainTradeParams calldata tradeParams
  ) external payable;

  function withdrawAndUnwrap(
    address recipient,
    uint256 amount,
    Permit calldata collateralPermit,
    OffChainBalancerParams calldata balancerParams
  ) external;

  function setWstethPoolId(bytes32 wstethPoolId) external;

  function getBaseToken() external view returns (IERC20);

  function getCollateral() external view returns (ICollateral);

  function getSwapRouter() external view returns (ISwapRouter);

  function getWstethVault() external view returns (IVault);

  function getWstethPoolId() external view returns (bytes32);

  function POOL_FEE_TIER() external view returns (uint24);
}

