// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IERC20Bound.sol";
import "./IAnima.sol";

import "./ManagerModifier.sol";

contract Anima is
  IAnima,
  ERC20,
  ERC20Burnable,
  ManagerModifier,
  ReentrancyGuard,
  Pausable
{
  //=======================================
  // Immutables
  //=======================================
  IERC20Bound public immutable BOUND;
  uint256 public immutable CAP;

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _bound,
    uint256 _cap
  ) ERC20("Anima", "ANIMA") ManagerModifier(_manager) {
    BOUND = IERC20Bound(_bound);
    CAP = _cap;
  }

  //=======================================
  // External
  //=======================================
  function mintFor(
    address _for,
    uint256 _amount
  ) external override onlyTokenMinter {
    // Check amount doesn't exceed cap
    require(ERC20.totalSupply() + _amount <= CAP, "Anima: Cap exceeded");

    // Mint
    _mint(_for, _amount);
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
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override {
    // Call super
    super._beforeTokenTransfer(from, to, amount);

    // Check if sender is manager
    if (!MANAGER.isManager(msg.sender, 0)) {
      // Check if minting or burning
      if (from != address(0) && to != address(0)) {
        // Check if token is unbound
        require(BOUND.isUnbound(address(this)), "Anima: Token not unbound");
      }
    }

    // Check if contract is paused
    require(!paused(), "Anima: Paused");
  }
}

