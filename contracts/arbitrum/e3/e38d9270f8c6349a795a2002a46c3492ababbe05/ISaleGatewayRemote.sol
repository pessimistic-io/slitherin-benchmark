// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface ISaleGatewayRemote {
  function dstChain() external view returns (uint240 chainID, uint16 lzChainID, address saleGateway);

  function gasForDestinationLzReceive() external view returns (uint256);

  function crossFee_d2() external view returns (uint256);

  function estimateFees(bytes calldata _payload) external view returns (uint256 fees);

  function buyToken(bytes calldata _payload, uint256 _tax) external payable;
}

