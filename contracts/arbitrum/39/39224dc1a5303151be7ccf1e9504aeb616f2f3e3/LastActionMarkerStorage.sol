// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ManagerModifier.sol";
import "./ILastActionMarkerStorage.sol";

contract LastActionMarkerStorage is ManagerModifier, ILastActionMarkerStorage {
  //=======================================
  // Mappings
  //=======================================
  // Token address -> Token Id -> Action Id -> timestamp/epoch
  mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
    private lastActionMarker;

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {}

  //=======================================
  // Functions
  //=======================================
  function setActionMarker(
    address _tokenAddress,
    uint256 _tokenId,
    uint256 _action,
    uint256 _marker
  ) external onlyManager {
    lastActionMarker[_tokenAddress][_tokenId][_action] = _marker;
  }

  function getActionMarker(
    address _tokenAddress,
    uint256 _tokenId,
    uint256 _action
  ) external view returns (uint256) {
    return lastActionMarker[_tokenAddress][_tokenId][_action];
  }
}

