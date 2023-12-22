// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.1;

import "./ERC677Gateway.sol";

interface ITransfer {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

contract ERC677Gateway_Pool is ERC677Gateway {
    constructor(
        address anyCallProxy,
        uint256 flag,
        address token
    ) ERC677Gateway(anyCallProxy, flag, token) {}

    function description() external pure returns (string memory) {
        return "ERC677Gateway_Pool";
    }

    function _swapout(uint256 amount, address sender)
        internal
        override
        returns (bool)
    {
        return ITransfer(token).transferFrom(sender, address(this), amount);
    }

    function _swapin(uint256 amount, address receiver)
        internal
        override
        returns (bool)
    {
        return ITransfer(token).transferFrom(address(this), receiver, amount);
    }
}

