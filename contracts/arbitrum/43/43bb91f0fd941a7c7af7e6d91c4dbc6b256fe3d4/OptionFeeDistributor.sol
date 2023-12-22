// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IERC20} from "./interfaces_IERC20.sol";

contract OptionFeeDistributor {
    address public constant address1 =
        0x6295df19A224615bE523FB728aB335885E97b54a;
    address public constant address2 =
        0x6295df19A224615bE523FB728aB335885E97b54a;

    function distribute(IERC20 token, uint256 amount) external {
        require(token.transferFrom(msg.sender, address(this), amount));

        uint256 half = amount / 4;
        uint256 otherHalf = amount - half;

        require(token.transfer(address1, half));
        require(token.transfer(address2, otherHalf));
    }
}

