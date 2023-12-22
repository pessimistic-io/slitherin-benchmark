// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "./IERC20Upgradeable.sol";

interface IMyceliumRouter {
  struct OneInchSwapDescription {
    IERC20Upgradeable srcToken;
    IERC20Upgradeable dstToken;
    address payable srcReceiver;
    address payable dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
    bytes permit;
  }

  error ZeroAddress();
  error SwapFailed();
  error Unauthorized();

  event RouterUpdated(address indexed newAddress, address indexed oldAddress);
  event SwapSuccess(
    address indexed receiver,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,
    uint256 amoutOut
  );

  function setRouter(address) external;
}

