// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IFundsCollector} from "./IFundsCollector.sol";
import {FundsHolder} from "./FundsHolder.sol";

contract Funds is IFundsCollector {
    using SafeERC20 for IERC20;

    FundsHolder public immutable fundsHolder;

    mapping(address withdrawalAddress => mapping(address owner => mapping(address token => uint256 balance)))
        public funds;

    constructor() {
        fundsHolder = new FundsHolder();
    }

    function collectFunds(
        address withdrawalAddress,
        address owner,
        address token,
        uint256 amount
    ) external {
        IERC20(token).safeTransferFrom(
            msg.sender,
            address(fundsHolder),
            amount
        );
        funds[withdrawalAddress][owner][token] += amount;
    }

    function withdrawToOwner(
        address withdrawalAddress,
        address token,
        uint256 amount
    ) external {
        funds[withdrawalAddress][msg.sender][token] -= amount;
        fundsHolder.transfer(token, amount, msg.sender);
    }

    function _useToken(
        address withdrawalAddress,
        address owner,
        address token
    ) internal {
        uint256 amount = funds[withdrawalAddress][owner][token];
        if (amount > 0) {
            funds[withdrawalAddress][owner][token] = 0;
            fundsHolder.transfer(token, amount, address(this));
        }
    }

    function _storeToken(
        address withdrawalAddress,
        address owner,
        address token
    ) internal {
        uint256 amount = IERC20(token).balanceOf(address(this));
        funds[withdrawalAddress][owner][token] += amount;
        if (amount > 0) {
            IERC20(token).safeTransfer(address(fundsHolder), amount);
        }
    }
}

