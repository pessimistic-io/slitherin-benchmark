// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {ISwapper} from "./ISwapper.sol";
import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";

contract OneInchSwapper is ISwapper {
    using SafeTransferLib for ERC20;
    address public immutable oneInch;

    constructor(address _oneInch) {
        oneInch = _oneInch;
    }

    function onSwapReceived(bytes calldata data) public {
        (bool success, ) = oneInch.call{value: address(this).balance}(data);
        require(success);
    }

    function approveTokenToOneInch(ERC20 token) public {
        token.safeApprove(oneInch, type(uint256).max);
    }
}

