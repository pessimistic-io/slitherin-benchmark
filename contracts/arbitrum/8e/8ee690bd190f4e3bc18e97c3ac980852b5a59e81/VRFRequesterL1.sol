pragma solidity ^0.8.0;

interface VRFRequesterL1 {
  function requestRandomness(uint256 requestId) external;
}

