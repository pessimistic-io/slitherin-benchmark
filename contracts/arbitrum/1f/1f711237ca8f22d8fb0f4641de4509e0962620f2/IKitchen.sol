//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./UserAccessible_Constants.sol";
import "./TokenVault_Types.sol";

interface IKitchen {
  function cookFor (address from, uint playerId, uint itemId) external;
  function claimFor (address from, uint playerId, uint boostFactor) external;
}
