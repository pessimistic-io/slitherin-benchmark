// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "./VRFConsumerBase.sol";

contract VRFCoordinatorMock {
  LinkTokenInterface public link;
  uint256 private _requestId = 10;

  address private _consumer;

  event RandomnessRequest(
    address indexed sender,
    bytes32 indexed keyHash,
    uint256 indexed seed
  );

  constructor(address linkAddress) {
    link = LinkTokenInterface(linkAddress);
  }

  function onTokenTransfer(
    address sender,
    uint256,
    bytes memory _data
  ) public onlyLINK {
    (bytes32 keyHash, uint256 seed) = abi.decode(_data, (bytes32, uint256));
    emit RandomnessRequest(sender, keyHash, seed);
  }

  function setConsumer(address consumer) public {
    _consumer = consumer;
  }

  function callBackWithRandomness(
    bytes32 requestId,
    uint256 randomness,
    address consumerContract
  ) public {
    VRFConsumerBase v;
    bytes memory resp = abi.encodeWithSelector(
      v.rawFulfillRandomness.selector,
      requestId,
      randomness
    );
    uint256 b = 206000;
    require(gasleft() >= b, "not enough gas for consumer");
    (bool success, ) = consumerContract.call(resp);
    require(success, "Issue with call");
  }

  modifier onlyLINK() {
    require(msg.sender == address(link), "Must use LINK token");
    _;
  }
}

