// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

contract Tosi is
  Initializable,
  ERC20Upgradeable,
  ERC20BurnableUpgradeable,
  PausableUpgradeable,
  OwnableUpgradeable,
  UUPSUpgradeable
{
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __ERC20_init("Tosi", "TOSI");
    __ERC20Burnable_init();
    __Pausable_init();
    __Ownable_init();
    __UUPSUpgradeable_init();
  }

  function pause() public onlyOwner {
    _pause();
  }

  function unpause() public onlyOwner {
    _unpause();
  }

  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override whenNotPaused {
    super._beforeTokenTransfer(from, to, amount);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

  function getImplementation() external view returns (address) {
    return _getImplementation();
  }
}

