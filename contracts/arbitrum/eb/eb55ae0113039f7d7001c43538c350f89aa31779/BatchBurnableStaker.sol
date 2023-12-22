// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC1155Holder.sol";
import "./ERC1155.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";

import "./ManagerModifier.sol";
import "./IBatchBurnableStaker.sol";
import "./IBatchBurnableStructure.sol";

contract BatchBurnableStaker is
  ERC1155Holder,
  ReentrancyGuard,
  Pausable,
  ManagerModifier,
  IBatchBurnableStaker
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
  // Events
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

  event Burned(
    uint256 realmId,
    address staker,
    address entityAddress,
    uint256 entityId,
    uint256 amount
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager, address _realm) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
  }

  //=======================================
  // External
  //=======================================
  function stakeBatchFor(
    address _staker,
    address _addr,
    uint256[] calldata _realmIds,
    uint256[] calldata _ids,
    uint256[] calldata _amounts
  ) external nonReentrant whenNotPaused onlyManager {
    for (uint256 j = 0; j < _ids.length; j++) {
      uint256 realmId = _realmIds[j];
      uint256 id = _ids[j];
      uint256 amount = _amounts[j];

      // Check if amount is greater than zero
      require(amount > 0, "BatchStaker: Amount must be above 0");

      // Remove from balance
      stakerBalance[realmId][_addr][id] += amount;

      emit Staked(realmId, _staker, _addr, id, amount);
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
    uint256[] calldata _realmIds,
    uint256[] calldata _ids,
    uint256[] calldata _amounts
  ) external nonReentrant whenNotPaused onlyManager {
    for (uint256 j = 0; j < _ids.length; j++) {
      // Only Realm owner can unstake
      uint256 realmId = _realmIds[j];
      _onlyOwner(realmId, _staker);

      uint256 id = _ids[j];
      uint256 amount = _amounts[j];

      // Check if amount is greater than zero
      require(amount > 0, "BatchBurnableStaker: Amount must be above 0");

      // Check balance
      require(
        stakerBalance[realmId][_addr][id] >= amount,
        "BatchBurnableStaker: Not enough balance"
      );

      // Add to balance
      stakerBalance[realmId][_addr][id] -= amount;

      emit Unstaked(realmId, _staker, _addr, id, amount);
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

  function burnBatchFor(
    address _addr,
    uint256[] calldata _realmIds,
    uint256[] calldata _ids,
    uint256[] calldata _amounts
  ) external nonReentrant whenNotPaused onlyManager {
    for (uint256 j = 0; j < _ids.length; j++) {
      uint256 realmId = _realmIds[j];

      uint256 id = _ids[j];
      uint256 amount = _amounts[j];

      // Check if amount is greater than zero
      require(amount > 0, "BatchBurnableStaker: Amount must be above 0");

      // Check balance
      require(
        stakerBalance[realmId][_addr][id] >= amount,
        "BatchBurnableStaker: Not enough balance"
      );

      // Remove from balance
      stakerBalance[realmId][_addr][id] -= amount;

      emit Burned(realmId, REALM.ownerOf(realmId), _addr, id, amount);
    }

    // Burn structures
    IBatchBurnableStructure(_addr).burnBatchFor(address(this), _ids, _amounts);
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
  function _onlyOwner(uint256 _realmId, address _staker) internal view {
    address owner = REALM.ownerOf(_realmId);
    require(owner == _staker, "BatchStakerV2: You do not own this Realm");
  }
}

