// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Libraries
import { SafeERC20 } from "./SafeERC20.sol";

// Interfaces
import { IERC20 } from "./IERC20.sol";
import { IYieldMint } from "./IYieldMint.sol";
import { I1inchAggregationRouterV4 } from "./I1inchAggregationRouterV4.sol";

contract DiamondPepeNFTs1inchRouter {
  using SafeERC20 for IERC20;

  I1inchAggregationRouterV4 public aggregationRouterV4;
  IYieldMint public yieldMint;
  IERC20 public rdpx;

  /// @notice Constructor
  /// @param _aggregationRouterV4Address address of 1inch V4 Aggregation Router
  /// @param _yieldMintAddress address of NFT contract for minting
  /// @param _rdpxAddress address of RDPX
  constructor(
    address payable _aggregationRouterV4Address,
    address _yieldMintAddress,
    address _rdpxAddress
  ) {
    aggregationRouterV4 = I1inchAggregationRouterV4(
      _aggregationRouterV4Address
    );
    yieldMint = IYieldMint(_yieldMintAddress);
    rdpx = IERC20(_rdpxAddress);
  }

  /// @param _caller aggregation executor that executes calls described in data
  /// @param _desc struct composed by srcToken, dstToken, srcReceiver, dstReceiver, amount, minReturnAmount, flags, permit
  /// @param _data encoded calls that caller should execute in between of swaps
  function swapAndDeposit(
    address _caller,
    I1inchAggregationRouterV4.SwapDescription memory _desc,
    bytes calldata _data
  ) external returns (bool) {
    IERC20 tokenFrom = IERC20(_desc.srcToken);
    tokenFrom.safeTransferFrom(msg.sender, address(this), _desc.amount);
    tokenFrom.safeApprove(address(aggregationRouterV4), _desc.amount);

    (uint256 returnAmount, ) = aggregationRouterV4.swap(_caller, _desc, _data);

    yieldMint.depositWeth{ value: returnAmount }(msg.sender);
    _transferLeftoverBalance();

    return true;
  }

  /// @notice transfer leftover balances
  function _transferLeftoverBalance() internal returns (bool) {
    uint256 rdpxBalance = rdpx.balanceOf(address(this));
    if (rdpxBalance > 0) {
      rdpx.safeTransfer(msg.sender, rdpxBalance);
    }

    uint256 ethBalance = address(this).balance;
    if (ethBalance > 0) {
      payable(msg.sender).transfer(ethBalance);
    }

    return true;
  }
}

