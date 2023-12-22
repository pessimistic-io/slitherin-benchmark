// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./Ownable.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";

contract BeefyTreasury is Ownable {
    using SafeERC20 for IERC20;

    function withdrawTokens(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function withdrawNative(address payable _to, uint256 _amount) external onlyOwner {
        _to.transfer(_amount);
    }

    receive () external payable {}
}
