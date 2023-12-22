// SPDX-License-Identifier: MIT
pragma solidity >0.7.5;

import "./SafeMath.sol";
import "./IERC20.sol";

// Paraswap's Camelot router
contract CamelotExchangeRouter {
  using SafeMath for uint256;

  /*solhint-disable var-name-mixedcase*/
  address private constant ETH_IDENTIFIER = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
  // Pool bits are 255-161: fee, 160: direction flag, 159-0: address
  uint256 private constant FEE_OFFSET = 161;
  uint256 private constant DIRECTION_FLAG = 0x0000000000000000000000010000000000000000000000000000000000000000;

  /*solhint-enable var-name-mixedcase */

  /*solhint-disable no-empty-blocks */
  receive() external payable {}

  /*solhint-enable no-empty-blocks */

  function swap(
    address tokenIn,
    uint256 amountIn,
    uint256 amountOutMin,
    address weth,
    uint256[] calldata pools
  ) external payable returns (uint256 tokensBought) {
    return _swap(tokenIn, amountIn, amountOutMin, weth, pools);
  }

  function _swap(
    address tokenIn,
    uint256 amountIn,
    uint256 amountOutMin,
    address weth,
    uint256[] memory pools
  ) private returns (uint256 tokensBought) {
    uint256 pairs = pools.length;

    require(pairs != 0, "At least one pool required");

    bool tokensBoughtEth;

    if (tokenIn == ETH_IDENTIFIER) {
      require(amountIn == msg.value, "Incorrect amount of ETH sent");
      IWETH(weth).deposit{ value: msg.value }();
      require(IWETH(weth).transfer(address(pools[0]), msg.value));
    } else {
      TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(pools[0]), amountIn);
      tokensBoughtEth = weth != address(0);
    }

    tokensBought = amountIn;

    for (uint256 i = 0; i < pairs; ++i) {
      uint256 p = pools[i];
      address pool = address(uint160(p));
      bool direction = p & DIRECTION_FLAG == 0;

      address tokenA = direction ? ICamelotPair(pool).token0() : ICamelotPair(pool).token1();
      tokensBought = ICamelotPair(pool).getAmountOut(tokensBought, tokenA);

      (uint256 amount0Out, uint256 amount1Out) = direction
      ? (uint256(0), tokensBought)
      : (tokensBought, uint256(0));
      ICamelotPair(pool).swap(
        amount0Out,
        amount1Out,
        i + 1 == pairs ? (tokensBoughtEth ? address(this) : msg.sender) : address(pools[i + 1]),
        ""
      );
    }

    if (tokensBoughtEth) {
      IWETH(weth).withdraw(tokensBought);
      TransferHelper.safeTransferETH(msg.sender, tokensBought);
    }

    require(tokensBought >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
  }
}


abstract contract IWETH is IERC20 {
  function deposit() external payable virtual;

  function withdraw(uint256 amount) external virtual;
}

interface ICamelotPair {
  function getAmountOut(uint256, address) external view returns (uint256);

  function token0() external returns (address);

  function token1() external returns (address);

  function swap(
    uint256 amount0Out,
    uint256 amount1Out,
    address to,
    bytes calldata data
  ) external;

  function stableSwap() external returns (bool);
}

library TransferHelper {
  /// @notice Transfers tokens from the targeted address to the given destination
  /// @notice Errors with 'STF' if transfer fails
  /// @param token The contract address of the token to be transferred
  /// @param from The originating address from which the tokens will be transferred
  /// @param to The destination address of the transfer
  /// @param value The amount to be transferred
  function safeTransferFrom(
    address token,
    address from,
    address to,
    uint256 value
  ) internal {
    (bool success, bytes memory data) =
    token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
    require(success && (data.length == 0 || abi.decode(data, (bool))), 'STF');
  }

  /// @notice Transfers tokens from msg.sender to a recipient
  /// @dev Errors with ST if transfer fails
  /// @param token The contract address of the token which will be transferred
  /// @param to The recipient of the transfer
  /// @param value The value of the transfer
  function safeTransfer(
    address token,
    address to,
    uint256 value
  ) internal {
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
    require(success && (data.length == 0 || abi.decode(data, (bool))), 'ST');
  }

  /// @notice Approves the stipulated contract to spend the given allowance in the given token
  /// @dev Errors with 'SA' if transfer fails
  /// @param token The contract address of the token to be approved
  /// @param to The target of the approval
  /// @param value The amount of the given token the target will be allowed to spend
  function safeApprove(
    address token,
    address to,
    uint256 value
  ) internal {
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, to, value));
    require(success && (data.length == 0 || abi.decode(data, (bool))), 'SA');
  }

  /// @notice Transfers ETH to the recipient address
  /// @dev Fails with `STE`
  /// @param to The destination of the transfer
  /// @param value The value to be transferred
  function safeTransferETH(address to, uint256 value) internal {
    (bool success, ) = to.call{value: value}(new bytes(0));
    require(success, 'STE');
  }
}
