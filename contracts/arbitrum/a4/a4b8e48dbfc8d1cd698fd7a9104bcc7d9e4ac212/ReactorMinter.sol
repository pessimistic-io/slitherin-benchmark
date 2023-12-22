// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";
import "./IReactor.sol";

import "./ManagerModifier.sol";

contract ReactorMinter is ReentrancyGuard, Pausable, ManagerModifier {
  using SafeERC20 for IERC20;

  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;
  IReactor public immutable REACTOR;
  address public immutable VAULT_OC;
  IERC20 public immutable TOKEN;

  //=======================================
  // Uints
  //=======================================
  uint256 public cost;

  //=======================================
  // Int
  //=======================================
  uint256 public maxQuantity;

  //=======================================
  // Events
  //=======================================
  event Minted(
    uint256 startTokenId,
    address addr,
    uint256 quantity,
    uint256 costPerItem,
    uint256 totalCost
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _realm,
    address _manager,
    address _reactor,
    address _vault_oc,
    address _token,
    uint256 _cost,
    uint256 _maxQuantity
  ) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
    REACTOR = IReactor(_reactor);
    VAULT_OC = _vault_oc;

    TOKEN = IERC20(_token);

    cost = _cost;
    maxQuantity = _maxQuantity;
  }

  //=======================================
  // External
  //=======================================
  function mint(uint256 _quantity) external nonReentrant whenNotPaused {
    // Check if Realm owner
    require(
      REALM.balanceOf(msg.sender) > 0,
      "ReactorMinter: Must be Realm owner"
    );

    // Check quantity is between 0 and maxQuantity
    require(
      _quantity > 0 && _quantity <= maxQuantity,
      "ReactorMinter: Quantity must be less than max allowed"
    );

    // Calculate costs
    uint256 totalCost = cost * _quantity;

    // Transfer to vault_oc
    TOKEN.safeTransferFrom(msg.sender, VAULT_OC, totalCost);

    // Mint
    uint256 startTokenId = REACTOR.mintFor(msg.sender, _quantity);

    emit Minted(startTokenId, address(REACTOR), _quantity, cost, totalCost);
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

  function updateCost(uint256 _cost) external onlyAdmin {
    cost = _cost;
  }
}

