//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TokenAccess_Types.sol";

interface ITokenAccess {

  function getAddress (uint contractId) external view returns (address);
  function getType (uint contractId) external view returns (uint8);
  function getContract (uint contractId) external view returns (ContractMeta memory);

  function validToken (uint contractId, uint tokenId) external view returns (bool);

  function banToken (uint contractId, uint tokenId) external;
  function unbanToken (uint contractId, uint tokenId) external;

  function addContract (address addr, uint8 tokenType, bool active) external;
  function updateContractState (uint contractId, bool active) external;
  function updateContractMeta (uint contractId, address addr, uint8 tokenType) external;

}
