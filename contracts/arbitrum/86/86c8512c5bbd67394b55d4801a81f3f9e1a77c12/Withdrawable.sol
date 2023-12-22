// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Context.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

abstract contract Withdrawable is Ownable {
    using SafeERC20 for IERC20;
    using Address for address payable;

    function withdrawToken(IERC20 _token) external onlyOwner {
        _token.safeTransfer(msg.sender, _token.balanceOf(address(this)));
    }
    function withdrawETH() external onlyOwner {
        payable(_msgSender()).sendValue(address(this).balance);
    }

}
