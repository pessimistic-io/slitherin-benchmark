// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC1155Holder.sol";
import "./ERC1155.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";

import "./ManagerModifier.sol";

contract BatchStaker is
  ERC1155Holder,
  ReentrancyGuard,
  Pausable,
  ManagerModifier
{
  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => mapping(address => mapping(uint256 => uint256)))
    public stakerBalance;

  //=======================================
  // EVENTS
  //=======================================
  event Staked(
    uint256 realmId,
    address staker,
    address entityAddress,
    uint256 entityId,
    uint256 amount
  );
  event Unstaked(
    uint256 realmId,
    address staker,
    address entityAddress,
    uint256 entityId,
    uint256 amount
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(address _realm, address _manager) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
  }

  //=======================================
  // External
  //=======================================
  function stakeBatchFor(
    address _staker,
    address _addr,
    uint256 _realmId,
    uint256[] calldata _ids,
    uint256[] calldata _amounts
  ) external nonReentrant whenNotPaused onlyManager {
    for (uint256 j = 0; j < _ids.length; j++) {
      uint256 id = _ids[j];
      uint256 amount = _amounts[j];

      // Check if amount is greater than zero
      require(amount > 0, "BatchStaker: Amount must be above 0");

      // Add to balance
      stakerBalance[_realmId][_addr][id] += amount;

      emit Staked(_realmId, _staker, _addr, id, amount);
    }

    // Transfer cities
    ERC1155(_addr).safeBatchTransferFrom(
      _staker,
      address(this),
      _ids,
      _amounts,
      ""
    );
  }

  function unstakeBatchFor(
    address _staker,
    address _addr,
    uint256 _realmId,
    uint256[] calldata _ids,
    uint256[] calldata _amounts
  ) external nonReentrant whenNotPaused onlyManager {
    for (uint256 j = 0; j < _ids.length; j++) {
      // Only Realm owner can unstake
      _onlyStaker(_realmId, _staker);

      uint256 id = _ids[j];
      uint256 amount = _amounts[j];

      // Check if amount is greater than zero
      require(amount > 0, "BatchStaker: Amount must be above 0");

      // Check balance
      require(
        stakerBalance[_realmId][_addr][id] >= amount,
        "BatchStaker: Not enough balance"
      );

      // Add to balance
      stakerBalance[_realmId][_addr][id] -= amount;

      emit Unstaked(_realmId, _staker, _addr, id, amount);
    }

    // Transfer cities
    ERC1155(_addr).safeBatchTransferFrom(
      address(this),
      _staker,
      _ids,
      _amounts,
      ""
    );
  }

  function hasStaked(
    uint256 _realmId,
    address _addr,
    uint256 _id,
    uint256 _count
  ) external view returns (bool) {
    return stakerBalance[_realmId][_addr][_id] >= _count;
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

  //=======================================
  // Internal
  //=======================================
  function _onlyStaker(uint256 _realmId, address _staker) internal view {
    require(
      REALM.ownerOf(_realmId) == _staker,
      "StructureStaker: You do not own this Realm"
    );
  }
}

