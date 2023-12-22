// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./Pausable.sol";

import "./IParticle.sol";
import "./IAnima.sol";

import "./ManagerModifier.sol";

contract TokenAdminMinter is ManagerModifier, Pausable {
  //=======================================
  // Immutables
  //=======================================
  IParticle public immutable PARTICLE;
  IAnima public immutable ANIMA;

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _particle,
    address _anima
  ) ManagerModifier(_manager) {
    PARTICLE = IParticle(_particle);
    ANIMA = IAnima(_anima);
  }

  //=======================================
  // Admin
  //=======================================
  function mint(
    address[] calldata _recipients,
    uint256[] calldata _particle,
    uint256[] calldata _anima
  ) external whenNotPaused onlyAdmin {
    for (uint256 j = 0; j < _recipients.length; j++) {
      address recipient = _recipients[j];
      uint256 particle = _particle[j];
      uint256 anima = _anima[j];

      PARTICLE.mintFor(recipient, particle);
      ANIMA.mintFor(recipient, anima);
    }
  }

  function pause() external onlyAdmin {
    _pause();
  }

  function unpause() external onlyAdmin {
    _unpause();
  }
}

