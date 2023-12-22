// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";
import "./ICollectible.sol";

import "./ManagerModifier.sol";

contract PrimeConvergence is ReentrancyGuard, Pausable, ManagerModifier {
  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;
  ICollectible public immutable COLLECTIBLE;
  address public immutable COLLECTIBLE_HOLDER;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => address) public winners;

  //=======================================
  // Events
  //=======================================
  event Contributed(uint256 collectibleId, uint256 amount);

  //=======================================
  // Constructor
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
  function intoTheVoid(uint256 _collectibleId, uint256 _amount)
    external
    nonReentrant
    whenNotPaused
  {
    // Only allow collectibleIds above 9
    require(_collectibleId > 9, "PrimeConvergence: Invalid Collectible");

    // Check sender owns a Realm
    require(
      REALM.balanceOf(msg.sender) > 0,
      "PrimeConvergence: Must be Realm owner"
    );

    // Transfer collectibles
    COLLECTIBLE.safeTransferFrom(
      msg.sender,
      COLLECTIBLE_HOLDER,
      _collectibleId,
      _amount,
      ""
    );

    emit Contributed(_collectibleId, _amount);
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

