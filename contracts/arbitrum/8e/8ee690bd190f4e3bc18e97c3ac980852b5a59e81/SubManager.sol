// SPDX-License-Identifier: AGPL-3.0

// An example of a consumer contract that also owns and manages the subscription
pragma solidity ^0.8.0;

import "./interfaces_LinkTokenInterface.sol";
import "./VRFCoordinatorV2Interface.sol";

/*
https://docs.chain.link/docs/vrf-contracts/#configurations
*/
contract VRFv2SubscriptionManager {
  VRFCoordinatorV2Interface public coordinator;
  LinkTokenInterface public link;

  // Storage parameters
  uint256[] private _randomWords;
  uint64 private _subscriptionId;
  address private _owner;

  constructor(address _coordinator, address _link) {
    coordinator = VRFCoordinatorV2Interface(_coordinator);
    link = LinkTokenInterface(_link);
    _owner = msg.sender;
    //Create a new subscription when you deploy the contract.
    _createNewSubscription();
  }

  // Create a new subscription when the contract is initially deployed.
  function _createNewSubscription() private onlyOwner {
    // Create a subscription with a new subscription ID.
    _subscriptionId = coordinator.createSubscription();
    // Add this contract as a consumer of its own subscription.
    coordinator.addConsumer(_subscriptionId, address(this));
  }

  // Assumes this contract owns link.
  // 1000000000000000000 = 1 LINK
  function topUpSubscription(uint256 amount) external onlyOwner {
    link.transferAndCall(
      address(coordinator),
      amount,
      abi.encode(_subscriptionId)
    );
  }

  function addConsumer(address consumerAddress) external onlyOwner {
    // Add a consumer contract to the subscription.
    coordinator.addConsumer(_subscriptionId, consumerAddress);
  }

  function removeConsumer(address consumerAddress) external onlyOwner {
    // Remove a consumer contract from the subscription.
    coordinator.removeConsumer(_subscriptionId, consumerAddress);
  }

  function cancelSubscription(address receivingWallet) external onlyOwner {
    // Cancel the subscription and send the remaining LINK to a wallet address.
    coordinator.cancelSubscription(_subscriptionId, receivingWallet);
    _subscriptionId = 0;
  }

  // Transfer this contract's funds to an address.
  // 1000000000000000000 = 1 LINK
  function withdraw(uint256 amount, address to) external onlyOwner {
    link.transfer(to, amount);
  }

  modifier onlyOwner() {
    require(msg.sender == _owner);
    _;
  }
}

