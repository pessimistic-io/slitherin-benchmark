// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Treasury.sol";


contract FeesTreasury is Treasury, Ownable, ReentrancyGuard {

    function withdraw(
        string calldata reason,
        address token,
        uint256 amount,
        address to
    ) public onlyOwner nonReentrant {
        _withdraw(reason, token, amount, to);
    }

}

