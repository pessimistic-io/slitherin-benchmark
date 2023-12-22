pragma solidity ^0.8.0;

interface VRFConsumerLite {
  function fulfillRandomWords(uint256 requestId, uint32[] memory randomWords)
    external;
}

