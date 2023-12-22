// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ManagerModifier.sol";

interface ILastActionMarkerStorage {
  function setActionMarker(
    address _tokenAddress,
    uint256 _tokenId,
    uint256 _action,
    uint256 _marker
  ) external;

  function getActionMarker(
    address _tokenAddress,
    uint256 _tokenId,
    uint256 _action
  ) external view returns (uint256);
}

