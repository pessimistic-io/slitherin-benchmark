// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./IERC721Receiver.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";
import "./IStructureStaker.sol";
import "./ERC721A.sol";

import "./ManagerModifier.sol";

contract StructureStaker is
  IERC721Receiver,
  ReentrancyGuard,
  Pausable,
  ManagerModifier
{
  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;

  //=======================================
  // Structs
  //=======================================
  struct Staker {
    address staker;
    uint256 realmId;
    uint256 stakedAt;
  }

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => mapping(address => mapping(uint256 => Staker)))
    public stakers;

  mapping(uint256 => mapping(address => uint256)) public stakedTypes;
  mapping(uint256 => mapping(uint256 => uint256)) public data;

  //=======================================
  // Int
  //=======================================
  uint256 public maxBatch;

  //=======================================
  // EVENTS
  //=======================================
  event StructureStaked(
    uint256 realmId,
    address staker,
    address structureAddress,
    uint256 structureId
  );
  event StructureUnstaked(
    uint256 realmId,
    address staker,
    address structureAddress,
    uint256 structureId
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _realm,
    address _manager,
    uint256 _maxBatch
  ) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
    maxBatch = _maxBatch;
  }

  //=======================================
  // External
  //=======================================
  function stakeFor(
    address _staker,
    uint256 _realmId,
    address _addr,
    uint256 _structureId
  ) external nonReentrant whenNotPaused onlyManager {
    _stake(_staker, _realmId, _addr, _structureId);
  }

  function unstakeFor(
    address _staker,
    uint256 _realmId,
    address _addr,
    uint256 _structureId
  ) external nonReentrant whenNotPaused onlyManager {
    _unstake(_staker, _realmId, _addr, _structureId);
  }

  function stakeBatchFor(
    address _staker,
    uint256[] calldata _realmIds,
    address[] calldata _addrs,
    uint256[] calldata _structureIds
  ) external nonReentrant whenNotPaused onlyManager {
    uint256 j = 0;
    uint256 structureIdslength = _structureIds.length;

    // Check max batch
    require(
      structureIdslength <= maxBatch,
      "StructureStaker: Only allowed up to maxBatch"
    );

    // Get lengths of params
    uint256 realmIdsLength = _realmIds.length;
    uint256 addrslength = _addrs.length;

    // Iterate through structureIds
    for (; j < structureIdslength; j++) {
      uint256 realmId = realmIdsLength == 1 ? _realmIds[0] : _realmIds[j];
      address addr = addrslength == 1 ? _addrs[0] : _addrs[j];

      _stake(_staker, realmId, addr, _structureIds[j]);
    }
  }

  function unstakeBatchFor(
    address _staker,
    uint256[] calldata _realmIds,
    address[] calldata _addrs,
    uint256[] calldata _structureIds
  ) external nonReentrant whenNotPaused onlyManager {
    uint256 j = 0;
    uint256 structureIdslength = _structureIds.length;

    require(
      structureIdslength <= maxBatch,
      "StructureStaker: Only allowed up to maxBatch"
    );

    // Get lengths of params
    uint256 realmIdsLength = _realmIds.length;
    uint256 addrslength = _addrs.length;

    // Iterate through structureIds
    for (; j < structureIdslength; j++) {
      uint256 realmId = realmIdsLength == 1 ? _realmIds[0] : _realmIds[j];
      address addr = addrslength == 1 ? _addrs[0] : _addrs[j];

      _unstake(_staker, realmId, addr, _structureIds[j]);
    }
  }

  function getStaker(
    uint256 _realmId,
    address _addr,
    uint256 _structureId
  )
    external
    view
    returns (
      address,
      uint256,
      uint256
    )
  {
    Staker memory staker = stakers[_realmId][_addr][_structureId];

    return (staker.staker, staker.realmId, staker.stakedAt);
  }

  function hasStaked(
    uint256 _realmId,
    address _addr,
    uint256 _count
  ) external view returns (bool) {
    return stakedTypes[_realmId][_addr] > _count;
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
  // ERC721
  //=======================================

  function onERC721Received(
    address, // _operator,
    address, //_from,
    uint256, // _tokenId,
    bytes calldata //_data
  ) external pure override returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }

  //=======================================
  // Internal
  //=======================================
  function _stake(
    address _staker,
    uint256 _realmId,
    address _addr,
    uint256 _structureId
  ) internal {
    // Create staker
    Staker storage staker = stakers[_realmId][_addr][_structureId];
    staker.staker = _staker;
    staker.realmId = _realmId;
    staker.stakedAt = block.timestamp;

    // Add staker to staked mapping
    stakers[_realmId][_addr][_structureId] = staker;

    // Transfer Structure to contract
    ERC721A(_addr).safeTransferFrom(_staker, address(this), _structureId);

    // Add to stakedTypes
    stakedTypes[_realmId][_addr] += 1;

    emit StructureStaked(_realmId, _staker, _addr, _structureId);
  }

  function _unstake(
    address _staker,
    uint256 _realmId,
    address _addr,
    uint256 _structureId
  ) internal {
    // Only Realm owner can unstake
    _onlyStaker(_realmId, _staker);

    Staker storage staker = stakers[_realmId][_addr][_structureId];

    // Reset staker
    staker.staker = address(0);
    staker.realmId = 0;
    staker.stakedAt = 0;

    // Transfer Structure back to owner
    ERC721A(_addr).safeTransferFrom(address(this), _staker, _structureId);

    // Subtract from stakedTypes
    stakedTypes[_realmId][_addr] -= 1;

    emit StructureUnstaked(_realmId, _staker, _addr, _structureId);
  }

  function _onlyStaker(uint256 _realmId, address _staker) internal view {
    require(
      REALM.ownerOf(_realmId) == _staker,
      "StructureStaker: You do not own this Realm"
    );
  }
}

