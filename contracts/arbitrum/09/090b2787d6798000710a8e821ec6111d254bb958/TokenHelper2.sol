// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./Ownable.sol";

contract TokenHelper is Ownable {

    constructor() {
        _transferOwnership(0x319870DC1302e12E4Cc27b5169c9e87e23214583);
    }

    function sendToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    function sendEther(address to, uint256 amount) external onlyOwner {
    payable(to).transfer(amount);
    }
}
