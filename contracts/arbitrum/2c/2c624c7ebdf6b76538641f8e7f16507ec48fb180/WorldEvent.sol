// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";
import "./ICollectible.sol";

import "./ManagerModifier.sol";

contract WorldEvent is ReentrancyGuard, Pausable, ManagerModifier {
  IRealm public immutable REALM;
  ICollectible public immutable COLLECTIBLE;
  address public immutable COLLECTIBLE_HOLDER;

  mapping(uint256 => address) public winners;

  //=======================================
  // Contructor
  //=======================================
  constructor(
    address _realm,
    address _manager,
    address _collectible,
    address _collectibleHolder
  ) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
    COLLECTIBLE = ICollectible(_collectible);
    COLLECTIBLE_HOLDER = _collectibleHolder;
  }

  //=======================================
  // External
  //=======================================
  function lostDonkeyFound() external nonReentrant whenNotPaused {
    require(winners[2] == address(0), "WorldEvent: Done");

    require(REALM.balanceOf(msg.sender) > 0, "WorldEvent: Must be Realm owner");

    require(
      winners[0] != msg.sender &&
        winners[1] != msg.sender &&
        winners[2] != msg.sender,
      "WorldEvent: You already entered"
    );

    COLLECTIBLE.safeTransferFrom(msg.sender, COLLECTIBLE_HOLDER, 1, 10, "");

    if (winners[0] == address(0)) {
      winners[0] = msg.sender;
    } else if (winners[1] == address(0)) {
      winners[1] = msg.sender;
    } else if (winners[2] == address(0)) {
      winners[2] = msg.sender;
    }
  }

  //=======================================
  // Admin
  //=======================================
  function pause() external onlyAdmin {
    _pause();
  }

  function unpause() external onlyAdmin {
    _unpause();
  }
}

