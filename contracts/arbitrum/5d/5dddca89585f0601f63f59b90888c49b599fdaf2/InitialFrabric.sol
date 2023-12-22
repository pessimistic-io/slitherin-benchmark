// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./FrabricDAO.sol";

import "./IInitialFrabric.sol";

contract InitialFrabric is FrabricDAO, IInitialFrabricInitializable {
  mapping(address => ParticipantType) public participant;

  // The erc20 is expected to be fully initialized via JS during deployment
  function initialize(
    address _erc20,
    address[] calldata genesis,
    uint64 _votingPeriod,
    uint64 _queuePeriod,
    uint64 _lapsePeriod
  ) external override initializer {
    __FrabricDAO_init("Protocol", _erc20, _votingPeriod, _queuePeriod, _lapsePeriod, 100);

    __Composable_init("Frabric", false);
    supportsInterface[type(IInitialFrabric).interfaceId] = true;

    // Actually add the genesis participants
    for (uint256 i = 0; i < genesis.length; i++) {
      participant[genesis[i]] = ParticipantType.Genesis;
      emit ParticipantChange(ParticipantType.Genesis, genesis[i]);
    }
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() Composable("Frabric") initializer {}

  function canPropose(address proposer) public view override(DAO, IDAOCore) returns (bool) {
    return uint8(participant[proposer]) >= uint8(ParticipantType.Genesis);
  }

  function _completeSpecificProposal(uint256, uint256 _pType) internal pure override {
    revert errors.UnhandledEnumCase("InitialFrabric _completeSpecificProposal", _pType);
  }
}

