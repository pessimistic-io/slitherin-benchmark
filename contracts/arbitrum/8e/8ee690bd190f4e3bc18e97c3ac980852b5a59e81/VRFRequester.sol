pragma solidity ^0.8.0;

interface VRFRequester {
  function requestRandomness(uint32 wordCount)
    external
    returns (uint256 requestId);
}

