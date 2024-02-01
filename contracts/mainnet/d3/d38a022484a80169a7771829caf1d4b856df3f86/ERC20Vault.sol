// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable2Step.sol";
/*
* @author Karl
*/
contract ERC20Vault is Ownable2Step {
    using SafeERC20 for IERC20;

    IERC20 token;

    constructor(address _token, address _approveAddress) {
        token = IERC20(_token);
        token.safeIncreaseAllowance(_approveAddress, 2**256 - 1);
    }

    function withdrawal() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(owner(), balance);
    }
}

