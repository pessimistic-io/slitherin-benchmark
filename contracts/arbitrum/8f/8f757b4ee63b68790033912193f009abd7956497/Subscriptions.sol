// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Errors} from "./Errors.sol";
import {ISubscriptions} from "./ISubscriptions.sol";
import {IOperator} from "./IOperator.sol";
import {IQ} from "./IQ.sol";
import {IERC20} from "./IERC20.sol";

contract Subscriptions is ISubscriptions {
    address public operator;
    uint96 public subscriptionLimit;

    event Subscribe(address indexed managerAddress, address indexed subscriberAddress, address indexed subscriberAccountAddress, uint96 maxLimit);
    event Unsubscribe(address indexed managerAddress, address indexed subscriberAddress, address indexed subscriberAccountAddress);

    constructor(address _operator, uint96 _subscriptionLimit) {
        operator = _operator;
        subscriptionLimit = _subscriptionLimit; // type(uint96).max / subscriptionLimit - For eg. 79228162514264337593543950335 / 10_000e6 - 7.922816251426434e18 subscribers
    }

    function subscribe(address manager, uint96 maxLimit) external {
        _checkbalance(maxLimit);
        _subscribe(manager, maxLimit);
    }

    function subscribe(address[] calldata managers, uint96[] calldata maxLimit) external {
        if (managers.length != maxLimit.length) revert Errors.InputMismatch();
        uint256 i;
        uint96 amount;
        uint96 highestAmount;
        for (; i < managers.length;) {
            amount = maxLimit[i];
            highestAmount = amount > highestAmount ? amount : highestAmount;
            _subscribe(managers[i], amount);
            unchecked {
                ++i;
            }
        }
        _checkbalance(highestAmount);
    }

    function unsubscribe(address manager) external {
        _unsubscribe(manager);
    }

    function updateSubscription(address manager, uint96 maxLimit) external {
        _unsubscribe(manager);
        _checkbalance(maxLimit);
        _subscribe(manager, maxLimit);
    }

    function unsubscribe(address[] calldata managers) external {
        uint256 i;
        for (; i < managers.length;) {
            _unsubscribe(managers[i]);
            unchecked {
                ++i;
            }
        }
    }

    function getAllSubscribers(address manager) external view returns (address[] memory) {
        return IOperator(operator).getAllSubscribers(manager);
    }

    function getIsSubscriber(address manager, address subscriber) external view returns (bool) {
        return IOperator(operator).getIsSubscriber(manager, subscriber);
    }

    function getSubscriptionAmount(address manager, address subscriber) external view returns (uint96) {
        return IOperator(operator).getSubscriptionAmount(manager, subscriber);
    }

    function getTotalSubscribedAmountPerManager(address manager) external view returns (uint96) {
        return IOperator(operator).getTotalSubscribedAmountPerManager(manager);
    }

    function _subscribe(address manager, uint96 maxLimit) internal {
        if (manager == address(0)) revert Errors.ZeroAddress();
        if (maxLimit < 1e6) revert Errors.ZeroAmount();
        if (maxLimit > subscriptionLimit) revert Errors.MoreThanLimit();
        
        // external call for now and then get it from `_checkBalance`
        address subscriberAccountAddress = IOperator(operator).getTraderAccount(msg.sender);
        IOperator(operator).setSubscribe(manager, msg.sender, maxLimit);
        emit Subscribe(manager, msg.sender, subscriberAccountAddress, maxLimit);
    }

    function _unsubscribe(address manager) internal {
        if (manager == address(0)) revert Errors.ZeroAddress();

        address subscriberAccountAddress = IOperator(operator).getTraderAccount(msg.sender);
        IOperator(operator).setUnsubscribe(manager, msg.sender);
        emit Unsubscribe(manager, msg.sender, subscriberAccountAddress);
    }

    function _checkbalance(uint96 amount) internal view {
        address token = IOperator(operator).getAddress("DEFAULTSTABLECOIN");
        address traderAccount = IOperator(operator).getTraderAccount(msg.sender);
        uint256 balance = IERC20(token).balanceOf(traderAccount);
        if (traderAccount == address(0)) revert Errors.AccountNotExists();
        if (balance < amount) revert Errors.BalanceLessThanAmount();
    }
}

