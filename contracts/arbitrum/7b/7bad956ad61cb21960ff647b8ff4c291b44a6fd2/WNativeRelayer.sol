// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./SafeERC20.sol";

import "./IWNative.sol";
import "./IWNativeRelayer.sol";
import "./TransferHelper.sol";

contract WNativeRelayer is IWNativeRelayer {
    using SafeERC20 for IERC20;

    receive() external payable {}

    function withdraw(address _wNative, uint256 _amount) external override {
        IERC20(_wNative).safeTransferFrom(msg.sender, address(this), _amount);
        IWNative(_wNative).withdraw(_amount);
        TransferHelper.safeTransferETH(msg.sender, _amount);
    }
}

