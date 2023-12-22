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

    event Subscribe(
        address indexed managerAddress,
        address indexed subscriberAddress,
        address indexed subscriberAccountAddress,
        uint96 maxLimit
    );
    event Unsubscribe(
        address indexed managerAddress, address indexed subscriberAddress, address indexed subscriberAccountAddress
    );
    event UpdateSubscriptionLimit(uint96 newSubscriptionLimit);

    constructor(address _operator, uint96 _subscriptionLimit) {
        operator = _operator;
        subscriptionLimit = _subscriptionLimit; // type(uint96).max / subscriptionLimit - For eg. 79228162514264337593543950335 / 10_000e6 - 7.922816251426434e18 subscribers
    }

    function updateSubscriptionLimit(uint96 newSubscriptionLimit) external {
        address owner = IOperator(operator).getAddress("OWNER");
        if (msg.sender != owner) revert Errors.NotOwner();
        if (newSubscriptionLimit < 1e6) revert Errors.ZeroAmount();
        subscriptionLimit = newSubscriptionLimit;
        emit UpdateSubscriptionLimit(newSubscriptionLimit);
    }

    function subscribe(address manager, uint96 maxLimit) external {
        address subscriberAccountAddress = IOperator(operator).getTraderAccount(msg.sender);
        _checkbalance(subscriberAccountAddress, maxLimit);
        _subscribe(manager, subscriberAccountAddress, maxLimit);
    }

    function subscribe(address[] calldata managers, uint96[] calldata maxLimit) external {
        if (managers.length != maxLimit.length) revert Errors.InputMismatch();
        address subscriberAccountAddress = IOperator(operator).getTraderAccount(msg.sender);
        uint256 i;
        uint96 amount;
        uint96 highestAmount;
        for (; i < managers.length;) {
            amount = maxLimit[i];
            highestAmount = amount > highestAmount ? amount : highestAmount;
            _subscribe(managers[i], subscriberAccountAddress, amount);
            unchecked {
                ++i;
            }
        }
        _checkbalance(subscriberAccountAddress, highestAmount);
    }

    function unsubscribe(address manager) external {
        address subscriberAccountAddress = IOperator(operator).getTraderAccount(msg.sender);
        _unsubscribe(manager, subscriberAccountAddress);
    }

    function updateSubscription(address manager, uint96 maxLimit) external {
        address subscriberAccountAddress = IOperator(operator).getTraderAccount(msg.sender);
        uint96 subscriptionAmount = IOperator(operator).getSubscriptionAmount(manager, subscriberAccountAddress);
        _unsubscribe(manager, subscriberAccountAddress);
        if (maxLimit > subscriptionAmount) _checkbalance(subscriberAccountAddress, maxLimit);
        _subscribe(manager, subscriberAccountAddress, maxLimit);
    }

    function unsubscribe(address[] calldata managers) external {
        address subscriberAccountAddress = IOperator(operator).getTraderAccount(msg.sender);
        uint256 i;
        for (; i < managers.length;) {
            _unsubscribe(managers[i], subscriberAccountAddress);
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

    function _subscribe(address manager, address subscriberAccountAddress, uint96 maxLimit) internal {
        if (manager == address(0)) revert Errors.ZeroAddress();
        if (maxLimit < 1e6) revert Errors.ZeroAmount();
        if (maxLimit > subscriptionLimit) revert Errors.MoreThanLimit();

        IOperator(operator).setSubscribe(manager, subscriberAccountAddress, maxLimit);
        emit Subscribe(manager, msg.sender, subscriberAccountAddress, maxLimit);
    }

    function _unsubscribe(address manager, address subscriberAccountAddress) internal {
        if (manager == address(0)) revert Errors.ZeroAddress();

        IOperator(operator).setUnsubscribe(manager, subscriberAccountAddress);
        emit Unsubscribe(manager, msg.sender, subscriberAccountAddress);
    }

    function _checkbalance(address traderAccount, uint96 amount) internal view {
        address token = IOperator(operator).getAddress("DEFAULTSTABLECOIN");
        uint256 balance = IERC20(token).balanceOf(traderAccount);
        if (traderAccount == address(0)) revert Errors.AccountNotExists();
        if (balance < amount) revert Errors.BalanceLessThanAmount();
    }
}

