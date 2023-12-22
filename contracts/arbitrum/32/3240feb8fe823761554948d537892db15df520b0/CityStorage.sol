// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";

import "./ManagerModifier.sol";

contract CityStorage is ReentrancyGuard, ManagerModifier {
  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => uint256) public timer;
  mapping(uint256 => uint256) public nourishmentCredits;

  //=======================================
  // Events
  //=======================================
  event Built(uint256 realmId, uint256 _hours, uint256 timerSetTo);
  event AddedNourishmentCredit(
    uint256 realmId,
    uint256 amountAdded,
    uint256 total
  );
  event RemovedNourishmentCredit(
    uint256 realmId,
    uint256 amountAdded,
    uint256 total
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {}

  //=======================================
  // External
  //=======================================
  function build(uint256 _realmId, uint256 _hours)
    external
    nonReentrant
    onlyManager
  {
    require(timer[_realmId] <= block.timestamp, "CityStorage: Can't build yet");

    timer[_realmId] = block.timestamp + (_hours * 3600);

    emit Built(_realmId, _hours, timer[_realmId]);
  }

  function addNourishmentCredit(uint256 _realmId, uint256 _amount)
    external
    nonReentrant
    onlyManager
  {
    nourishmentCredits[_realmId] += _amount;

    emit AddedNourishmentCredit(
      _realmId,
      _amount,
      nourishmentCredits[_realmId]
    );
  }

  function removeNourishmentCredit(uint256 _realmId, uint256 _amount)
    external
    nonReentrant
    onlyManager
  {
    require(
      _amount <= nourishmentCredits[_realmId],
      "CityStorage: Not enough credits"
    );

    nourishmentCredits[_realmId] -= _amount;

    emit RemovedNourishmentCredit(
      _realmId,
      _amount,
      nourishmentCredits[_realmId]
    );
  }

  function canBuild(uint256 _realmId) external view returns (bool) {
    return timer[_realmId] <= block.timestamp;
  }
}

