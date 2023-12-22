// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IAdventurerGateway {
  function checkAddress(address _addr, bytes32[] calldata _proof) external view;
}

