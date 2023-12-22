// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IFundsCollector} from "./IFundsCollector.sol";
import {FundsStorage} from "./FundsStorage.sol";

contract FundsHolder is IFundsCollector {
    using SafeERC20 for IERC20;

    FundsStorage immutable _fundsStorage;

    mapping(address withdrawalAddress => mapping(address owner => mapping(address token => uint256 balance))) _balance;

    constructor() {
        _fundsStorage = new FundsStorage();
    }

    function collectFunds(
        address withdrawalAddress,
        address owner,
        address token,
        uint256 amount
    ) external {
        _balance[withdrawalAddress][owner][token] += amount;
        IERC20(token).safeTransferFrom(
            msg.sender,
            address(_fundsStorage),
            amount
        );
    }

    function withdrawToOwner(
        address withdrawalAddress,
        address owner,
        address token,
        uint256 amount
    ) external {
        _balance[withdrawalAddress][msg.sender][token] -= amount;
        _fundsStorage.moveFunds(token, amount, owner);
    }

    function _useFunds(
        address withdrawalAddress,
        address owner,
        address token
    ) internal {
        uint256 amount = _balance[withdrawalAddress][owner][token];
        if (amount > 0) {
            _balance[withdrawalAddress][owner][token] = 0;
            _fundsStorage.moveFunds(token, amount, address(this));
        }
    }

    function _storeFunds(
        address withdrawalAddress,
        address owner,
        address token
    ) internal {
        uint256 amount = IERC20(token).balanceOf(address(this));
        _balance[withdrawalAddress][owner][token] = amount;
        IERC20(token).safeTransfer(address(_fundsStorage), amount);
    }
}

