pragma solidity ^0.8.0;
import "./Characters.sol";

// Mocked endpoint for all of the basic distro flows
// In production this will be three seperate contracts, so build accordingly.
// This contract is simply meant to provide a clean mocked version of the primary endpointss
// needed for the basic distribution apps. Some functions _may_ change slightly, but generally
// integrating based on these mocks should allow us to integrate the completed contracts with little to no friction
// and provide a more stable, modular and accesible testing option for front-end testing.

contract CharacterGenMock is Characters {
  constructor(
    ICore _core,
    SelectableOptions _selectableOptions,
    Authority auth
  ) Characters(_core, _selectableOptions, auth) {}

  function equipOutfitAdmin(
    uint16 slotID,
    uint32 id,
    address _player
  ) external requiresAuth {
    _setOutfitSlot(slotID, outfits[getIdFromAddress(_player)], id, _player);
  }

  function equipSkeletonAdmin(
    uint16 slotID,
    uint32 id,
    address _player
  ) external requiresAuth {
    _setSkeletonSlot(slotID, skeletons[getIdFromAddress(_player)], id);
  }
}

