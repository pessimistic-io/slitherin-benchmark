// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IPublicLockV13.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract Hook {
    error NotAllowed(address lock, address recipient);

    mapping(address => mapping(address => bool)) public allowLists;

    constructor() {}

    function addToAllowList(address lock, address[] calldata allowed) public {
        if (!IPublicLockV13(lock).isLockManager(msg.sender)) {
            revert NotAllowed(lock, msg.sender);
        }
        for (uint256 i = 0; i < allowed.length; i++) {
            allowLists[lock][allowed[i]] = true;
        }
    }

    function isAllowed(
        address lock,
        address recipient
    ) public view returns (bool allowed) {
        return !!allowLists[lock][recipient];
    }

    function keyPurchasePrice(
        address /* from */,
        address recipient,
        address /* referrer */,
        bytes calldata /* data */
    ) external view returns (uint256 minKeyPrice) {
        uint price = IPublicLockV13(msg.sender).keyPrice();
        if (isAllowed(msg.sender, recipient)) {
            return price;
        }
        revert NotAllowed(msg.sender, recipient);
    }

    function onKeyPurchase(
        uint /* tokenId */,
        address /*from*/,
        address /*recipient*/,
        address /*referrer*/,
        bytes calldata /*data*/,
        uint256 /*minKeyPrice*/,
        uint256 /*pricePaid*/
    ) external {
        // Do nothing
    }
}

