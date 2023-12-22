// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Errors} from "./Errors.sol";
import {ISubscriptions} from "./ISubscriptions.sol";
import {IOperator} from "./IOperator.sol";
import {IQ} from "./IQ.sol";

contract Subscriptions is ISubscriptions {
    address public operator;
    uint96 public subscriptionLimit;

    event Subscribe(address indexed managerAddress, address indexed subscriberAddress, uint96 maxLimit);
    event Unsubscribe(address indexed managerAddress, address indexed subscriberAddress);

    constructor(address _operator, uint96 _subscriptionLimit) {
        operator = _operator;
        subscriptionLimit = _subscriptionLimit; // type(uint96).max / subscriptionLimit - For eg. 79228162514264337593543950335 / 10_000e6 - 7.922816251426434e18 subscribers
    }

    function subscribe(address manager, uint96 maxLimit) external {
        _subscribe(manager, maxLimit);
    }

    function subscribe(address[] calldata managers, uint96[] calldata maxLimit) external {
        if (managers.length != maxLimit.length) revert Errors.InputMismatch();
        uint256 i;
        for (; i < managers.length;) {
            _subscribe(managers[i], maxLimit[i]);
            unchecked {
                ++i;
            }
        }
    }

    function unsubscribe(address manager) external {
        _unsubscribe(manager);
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

        address traderAccount = IOperator(operator).getTraderAccount(msg.sender);
        address q = IOperator(operator).getAddress("Q");
        if (traderAccount == address(0)) traderAccount = IQ(q).createAccount(msg.sender);

        IOperator(operator).setSubscribe(manager, msg.sender, maxLimit);
        emit Subscribe(manager, msg.sender, maxLimit);
    }

    function _unsubscribe(address manager) internal {
        if (manager == address(0)) revert Errors.ZeroAddress();

        IOperator(operator).setUnsubscribe(manager, msg.sender);
        emit Unsubscribe(manager, msg.sender);
    }
}

