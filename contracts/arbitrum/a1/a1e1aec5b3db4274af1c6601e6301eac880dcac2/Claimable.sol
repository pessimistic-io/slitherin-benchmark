// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";

abstract contract Claimable is Ownable {
    function claim(address to, address asset, uint256 amount) public onlyOwner {
        if (asset == address(0)) {
            payable(to).transfer(amount);
            return;
        }

        IERC20(asset).transfer(to, amount);
    }
}

