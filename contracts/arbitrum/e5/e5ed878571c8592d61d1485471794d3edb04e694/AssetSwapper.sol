// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.7.6;

// Libraries
import {SafeERC20} from "./SafeERC20.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {IAssetSwapper} from "./IAssetSwapper.sol";

// Contracts
import {Ownable} from "./Ownable.sol";

/// @title Swaps tokens on Uniswap V3
/// @author Dopex
contract AssetSwapper is IAssetSwapper, Ownable {
  using SafeERC20 for IERC20;

  /// @dev Uniswap V2 SwapRouter
  IUniswapV2Router02 public uniV2Router;

  /// @dev weth address
  address public immutable weth;

  event NewSwapperAddress(address indexed swapper);

  constructor(address _router, address _weth) {
    require(_router != address(0), 'Uniswap v2 router address cannot be 0 address');
    require(_weth != address(0), 'WETH address cannot be 0 address');
    uniV2Router = IUniswapV2Router02(_router);
    weth = _weth;
  }

  function setSwapperContract(address _address) public onlyOwner returns (bool) {
    //check for zero address
    require(_address != address(0), 'E54');

    uniV2Router = IUniswapV2Router02(_address);
    emit NewSwapperAddress(_address);
    return true;
  }

  /// @dev Swaps between given `from` and `to` assets
  /// @param from From token address
  /// @param to To token address
  /// @param amount From token amount
  /// @param minAmountOut Minimum token amount to receive out
  /// @return To token amuount received
  function swapAsset(
    address from,
    address to,
    uint256 amount,
    uint256 minAmountOut
  ) public override returns (uint256) {
    IERC20(from).safeTransferFrom(msg.sender, address(this), amount);
    address[] memory path;
    if (from == weth || to == weth) {
      path = new address[](2);
      path[0] = from;
      path[1] = to;
    } else {
      path = new address[](3);
      path[0] = from;
      path[1] = weth;
      path[2] = to;
    }
    IERC20(from).safeApprove(address(uniV2Router), amount);
    uint256 amountOut = uniV2Router.swapExactTokensForTokens(
      amount,
      minAmountOut,
      path,
      address(this),
      block.timestamp
    )[path.length - 1];
    IERC20(to).safeTransfer(msg.sender, amountOut);
    return amountOut;
  }
}

