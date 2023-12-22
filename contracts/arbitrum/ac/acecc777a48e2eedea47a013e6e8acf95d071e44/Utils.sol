//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IWETH.sol";
import "./CustomErrors.sol";

library Utils {
  
  using SafeERC20 for IERC20;
  
  function roundUpDiv(uint dividend, uint divider) internal pure returns(uint) {
    uint adjustment = dividend % divider > 0? 1: 0;
    return dividend / divider + adjustment;
  }
  
  /// @notice Transfer fund from sender to receiver, with handling of ETH wrapping and unwrapping
  /// if needed. Note that this function will not perform balance check and it should be done
  /// in the caller.
  /// @param sender Account of the sender
  /// @param receiver Account of the receiver
  /// @param amount Size of the fund to be transferred from sender to receiver
  /// @param isSendingETH Indicate if sender is sending fund with ETH
  /// @param isReceivingETH Indicate if receiver is receiving fund with ETH
  function transferTokenOrETH(
                              address sender,
                              address receiver,
                              uint amount,
                              IERC20 underlying,
                              address wethAddress,
                              bool isSendingETH,
                              bool isReceivingETH
                              ) internal {
    address sender_ = sender;
    address receiver_ = receiver;
    
    // If it is ETH transfer, contract will send/receive on behalf
    // and do needed token wrapping/unwrapping
    if (isSendingETH) {
      sender_ = address(this);
    }
    if (isReceivingETH) {
      receiver_ = address(this);
    }
    
    // If sender uses ETH for transfer, token wrapping is needed
    if (isSendingETH) {
      IWETH weth = IWETH(wethAddress);
      weth.deposit{ value: amount }();
    }
    
    // Transfer `amount` from sender to receiver
    if (sender_ == address(this)) {
      underlying.safeTransfer(receiver_, amount);
    } else {
      underlying.safeTransferFrom(sender_, receiver_, amount);
    }
    
    // For receiver getting ETH in transfer, token unwrapping is needed
    if (isReceivingETH) {
      IWETH weth = IWETH(wethAddress);
      weth.withdraw(amount);
      (bool success,) = receiver.call{value: amount}("");
      if (!success) {
        revert CustomErrors.UTL_UnsuccessfulEthTransfer();
      }
    }
  }
  
}
