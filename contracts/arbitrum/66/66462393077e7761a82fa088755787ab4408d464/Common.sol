// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;
pragma abicoder v2;

abstract contract Common {
    uint256 public buyTotalTax;
    uint256 public sellTotalTax;

    function _innerTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual;
}

