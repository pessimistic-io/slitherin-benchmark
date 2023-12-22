// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";
import "./IMagicRefinery.sol";
import "./IMagicRefineryData.sol";

import "./ManagerModifier.sol";

contract MagicRefineryMinter is ReentrancyGuard, Pausable, ManagerModifier {
  using SafeERC20 for IERC20;

  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;
  IMagicRefinery public immutable REFINERY;
  IMagicRefineryData public immutable DATA;
  address public immutable VAULT;
  address public immutable VAULT_OC;
  IERC20 public immutable TOKEN;

  //=======================================
  // Mapppings
  //=======================================
  mapping(uint256 => uint256) public costs;

  //=======================================
  // Int
  //=======================================
  uint256 public maxQuantity;

  //=======================================
  // Events
  //=======================================
  event Minted(uint256 id, address addr, uint256 tier, uint256 tierCost);

  event MintedTotals(
    uint256 tier,
    uint256 quantity,
    uint256 totalCost,
    uint256 toalCut
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _realm,
    address _manager,
    address _refinery,
    address _refineryData,
    address _vault,
    address _vault_oc,
    address _token,
    uint256[3] memory _tiers,
    uint256 _maxQuantity
  ) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
    REFINERY = IMagicRefinery(_refinery);
    DATA = IMagicRefineryData(_refineryData);
    VAULT = _vault;
    VAULT_OC = _vault_oc;

    TOKEN = IERC20(_token);

    costs[0] = _tiers[0];
    costs[1] = _tiers[1];
    costs[2] = _tiers[2];

    maxQuantity = _maxQuantity;
  }

  //=======================================
  // External
  //=======================================
  function mint(uint256 _tier, uint256 _quantity) external nonReentrant {
    // Check quantity is between 0 and maxQuantity
    require(
      _quantity > 0 && _quantity <= maxQuantity,
      "MagicRefineryMinter: Quantity must be less than max allowed"
    );

    // Check tier is between 0 and 2
    require(_tier <= 2, "MagicRefineryMinter: Tier must be 0 to 2");

    // Check if Realm owner
    require(
      REALM.balanceOf(msg.sender) > 0,
      "MagicRefineryMinter: Must be Realm owner"
    );

    // Get tier cost
    uint256 tierCost = costs[_tier];

    // Calculate costs
    uint256 totalCost = tierCost * _quantity;
    uint256 cut = totalCost / 10;
    uint256 cost = totalCost - cut;

    // Transfer to vault
    TOKEN.safeTransferFrom(msg.sender, VAULT, cost);

    // Transfer to vault_oc
    TOKEN.safeTransferFrom(msg.sender, VAULT_OC, cut);

    // Mint
    uint256 startTokenId = REFINERY.mintFor(msg.sender, _quantity);

    // Create data
    uint256 j = 0;
    for (; j < _quantity; j++) {
      uint256 id = j + startTokenId;
      DATA.create(id, _tier, tierCost);

      emit Minted(id, address(REFINERY), _tier, tierCost);
    }

    emit MintedTotals(_tier, _quantity, cost, cut);
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

  function updateCost(uint256 _tier, uint256 _cost) external onlyAdmin {
    costs[_tier] = _cost;
  }

  function updateMaxQuantity(uint256 _maxQuantity) external onlyAdmin {
    maxQuantity = _maxQuantity;
  }
}

