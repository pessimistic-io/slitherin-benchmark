// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface ISubscriptions {
    function getAllSubscribers(address managerAddress) external view returns (address[] memory);
    function getIsSubscriber(address manager, address subscriber) external view returns (bool);
    function getSubscriptionAmount(address manager, address subscriber) external view returns (uint96);
    function getTotalSubscribedAmountPerManager(address manager) external view returns (uint96);
}

