// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Context.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

abstract contract Withdrawable is Ownable {
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public treasury;

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function withdrawToken(IERC20 _token, uint _amount) external onlyOwner {
        _token.safeTransfer(treasury, _amount);
    }

    function withdrawETH(uint _amount) external onlyOwner {
        payable(treasury).sendValue(_amount);
    }

    function withdrawTokenAll(IERC20 _token) external onlyOwner {
        _token.safeTransfer(treasury, _token.balanceOf(address(this)));
    }

    function withdrawETHAll() external onlyOwner {
        payable(treasury).sendValue(address(this).balance);
    }
}

