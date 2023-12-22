// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { IERC721 } from "./IERC721.sol";
import { IERC1155 } from "./IERC1155.sol";

import { LibSweep, AllReverted, InvalidMsgValue } from "./LibSweep.sol";

import { SettingsBitFlag } from "./SettingsBitFlag.sol";
import { ITroveMarketplace } from "./ITroveMarketplace.sol";
import { IShiftSweeper } from "./IShiftSweeper.sol";
import { BuyError } from "./BuyError.sol";
import { MultiTokenBuyOrder, BuyOrder } from "./BuyOrder.sol";

import { IUniswapV2Router02 } from "./IUniswapV2Router02.sol";
import { SwapInput, InputType, SwapNode } from "./SwapInput.sol";

// import "@forge-std/src/console.sol";

import { WithOwnership } from "./LibOwnership.sol";

contract SweepFacet is WithOwnership, IShiftSweeper {
  using SafeERC20 for IERC20;

  function buyOrdersMultiTokens(
    MultiTokenBuyOrder[] calldata _buyOrders,
    uint16 _inputSettingsBitFlag,
    address[] calldata _paymentTokens,
    uint256[] calldata _maxSpendIncFees
  ) external payable {
    uint256 length = _paymentTokens.length;

    for (uint256 i = 0; i < length; ) {
      if (_paymentTokens[i] == address(0)) {
        if (_maxSpendIncFees[i] != msg.value) revert InvalidMsgValue();
      } else {
        // if (msg.value != 0) revert MsgValueShouldBeZero();
        // transfer payment tokens to this contract
        IERC20(_paymentTokens[i]).safeTransferFrom(
          msg.sender,
          address(this),
          _maxSpendIncFees[i]
        );
      }
      unchecked {
        ++i;
      }
    }

    (uint256[] memory totalSpentAmounts, uint256 successCount) = LibSweep
      ._buyOrdersMultiTokens(
        _buyOrders,
        _inputSettingsBitFlag,
        _paymentTokens,
        LibSweep._maxSpendWithoutFees(_maxSpendIncFees)
      );

    // transfer back failed payment tokens to the buyer
    if (successCount == 0) revert AllReverted();

    LibSweep._refundBuyerAllPaymentTokens(
      _paymentTokens,
      _maxSpendIncFees,
      totalSpentAmounts
    );
  }
}

