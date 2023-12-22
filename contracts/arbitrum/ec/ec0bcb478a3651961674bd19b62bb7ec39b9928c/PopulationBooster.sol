// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";
import "./ICollectible.sol";
import "./ICityStorage.sol";

import "./ManagerModifier.sol";

contract PopulationBooster is ReentrancyGuard, Pausable, ManagerModifier {
  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;
  ICollectible public immutable COLLECTIBLE;
  ICityStorage public immutable CITY_STORAGE;
  address public immutable COLLECTIBLE_HOLDER;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => bool) public nourishmentIds;

  //=======================================
  // Events
  //=======================================
  event Boosted(
    uint256 realmId,
    uint256 collectibleId,
    uint256 collectibleAmount
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _realm,
    address _manager,
    address _collectible,
    address _cityStorage,
    address _collectibleHolder
  ) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
    COLLECTIBLE = ICollectible(_collectible);
    CITY_STORAGE = ICityStorage(_cityStorage);
    COLLECTIBLE_HOLDER = _collectibleHolder;

    nourishmentIds[0] = true;
    nourishmentIds[1] = true;
    nourishmentIds[2] = true;
    nourishmentIds[3] = true;
    nourishmentIds[4] = true;
    nourishmentIds[5] = true;
    nourishmentIds[6] = true;
    nourishmentIds[7] = true;
    nourishmentIds[8] = true;
    nourishmentIds[9] = true;
  }

  //=======================================
  // External
  //=======================================
  function boost(
    uint256[] calldata _realmIds,
    uint256[][] calldata _collectibleIds,
    uint256[][] calldata _collectibleAmounts
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _realmIds.length; j++) {
      uint256 realmId = _realmIds[j];
      uint256[] memory collectibleIds = _collectibleIds[j];
      uint256[] memory collectibleAmounts = _collectibleAmounts[j];

      // Check if Realm owner
      require(
        REALM.ownerOf(realmId) == msg.sender,
        "PopulationBooster: Must be Realm owner"
      );

      for (uint256 h = 0; h < collectibleIds.length; h++) {
        uint256 collectibleId = collectibleIds[h];
        uint256 amount = collectibleAmounts[h];

        // Check collectibleId is nourishment
        require(
          nourishmentIds[collectibleId],
          "PopulationBooster: Not a nourishment collectible"
        );

        // Remove nourishment credits
        CITY_STORAGE.removeNourishmentCredit(realmId, amount);

        emit Boosted(realmId, collectibleId, amount);
      }

      // Burn collectibles
      COLLECTIBLE.safeBatchTransferFrom(
        msg.sender,
        COLLECTIBLE_HOLDER,
        collectibleIds,
        collectibleAmounts,
        ""
      );
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

