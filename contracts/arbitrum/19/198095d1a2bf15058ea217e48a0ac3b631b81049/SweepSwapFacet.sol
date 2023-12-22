// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./IERC1155.sol";
import "./SafeERC20.sol";

import "./LibSweep.sol";
import "./OwnershipFacet.sol";

import "./ANFTReceiver.sol";
import "./SettingsBitFlag.sol";
import "./ITroveMarketplace.sol";
import "./IShiftSweeper.sol";
import "./BuyError.sol";

import "./BuyOrder.sol";

import "./IUniswapV2Router02.sol";

import "./SwapInput.sol";

// import "@forge-std/src/console.sol";

error WrongInputType();

/// @title SweepSwapFacet
/// @author karmabadger
/// @notice This facet allows the owner to swap tokens to buy items from nft marketplaces
/// @dev Swaps are first performed and swapped into payment tokens and then the payment tokens are used to buy items.
/// @dev each SwapInput struct represents a swap and the payment token is the output token of the swap. It can be multiple swaps chained together but the final output tokens needs to be a payment token.
contract SweepSwapFacet is OwnershipModifers {
  using SafeERC20 for IERC20;
  using SettingsBitFlag for uint16;

  function swapOrdersMultiTokens(
    MultiTokenBuyOrder[] calldata _buyOrders,
    uint16 _inputSettingsBitFlag,
    address[] calldata _paymentTokens,
    SwapInput[] calldata _swapsArrs
  ) external payable {
    uint256 length = _swapsArrs.length; // memoize length

    // Check if the sum of ETH used is less than the msg.value
    uint256 sumETHUsed = 0;
    for (uint256 i = 0; i < length; i++) {
      SwapInput memory swapInput = _swapsArrs[i];
      if (swapInput.swapNodes[0].ETHIn) {
        sumETHUsed += swapInput.swapNodes[0].amountIn;
      }
    }
    if (sumETHUsed > msg.value) revert("Not enough ETH");

    // perform swaps
    uint256[] memory amounts = new uint256[](_paymentTokens.length); // memoize amounts returned from swap
    for (uint256 i = 0; i < length; i++) {
      SwapInput memory swapInput = _swapsArrs[i];

      if (swapInput.inputType == InputType.PAYMENT_TOKEN) {
        if (!swapInput.swapNodes[0].ETHIn) {
          IERC20(_paymentTokens[swapInput.outTokenIndex]).safeTransferFrom(
            msg.sender,
            address(this),
            swapInput.swapNodes[0].amountIn
          );
        }
        amounts[swapInput.outTokenIndex] += swapInput.swapNodes[0].amountIn;
      } else if (swapInput.inputType == InputType.SWAP_EXACT_IN_TO_OUT) {
        uint256 swapLength = swapInput.swapNodes.length;
        uint256[] memory swapAmountsOut = new uint256[](swapLength);
        for (uint256 j = 0; j < swapLength; j++) {
          if (!swapInput.swapNodes[0].ETHIn) {
            IERC20(swapInput.swapNodes[0].path[0]).safeTransferFrom(
              msg.sender,
              address(this),
              swapInput.swapNodes[0].amountIn
            );
            IERC20(swapInput.swapNodes[0].path[0]).safeApprove(
              swapInput.swapNodes[0].router,
              swapInput.swapNodes[0].amountIn
            );
          }

          SwapNode memory swapNode = swapInput.swapNodes[j];
          uint256 amountIn = (j == 0)
            ? swapNode.amountIn
            : swapAmountsOut[j - 1];
          uint256 amountOutMin = swapNode.amountOut;

          if (swapNode.ETHIn) {
            uint256[] memory amountsOut = IUniswapV2Router02(swapNode.router)
              .swapExactETHForTokens{ value: amountIn }(
              amountOutMin,
              swapNode.path,
              address(this),
              swapNode.deadline
            );
            swapAmountsOut[j] = amountsOut[amountsOut.length - 1];
          } else if (swapNode.ETHOut) {
            uint256[] memory amountsOut = IUniswapV2Router02(swapNode.router)
              .swapExactTokensForETH(
                amountIn,
                amountOutMin,
                swapNode.path,
                address(this),
                swapNode.deadline
              );
            swapAmountsOut[j] = amountsOut[amountsOut.length - 1];
          } else {
            uint256[] memory amountsOut = IUniswapV2Router02(swapNode.router)
              .swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                swapNode.path,
                address(this),
                swapNode.deadline
              );
            swapAmountsOut[j] = amountsOut[amountsOut.length - 1];
          }
        }
        amounts[swapInput.outTokenIndex] += swapAmountsOut[swapLength - 1];
      } else if (swapInput.inputType == InputType.SWAP_IN_TO_EXACT_OUT) {
        revert("Not implemented yet");
      } else revert WrongInputType();
    }

    (uint256[] memory totalSpentAmounts, uint256 successCount) = LibSweep
      ._buyOrdersMultiTokens(
        _buyOrders,
        _inputSettingsBitFlag,
        _paymentTokens,
        LibSweep._maxSpendWithoutFees(amounts)
      );

    // transfer back failed payment tokens to the buyer
    if (successCount == 0) revert AllReverted();

    LibSweep._refundBuyerAllPaymentTokens(
      _paymentTokens,
      amounts,
      totalSpentAmounts
    );
  }
}

