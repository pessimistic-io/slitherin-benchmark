// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC721.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IMagicRefinery.sol";
import "./ERC721A.sol";

import "./ManagerModifier.sol";
import "./IMagicRefineryData.sol";

contract MagicRefineryRedeem is ReentrancyGuard, Pausable, ManagerModifier {
  using SafeERC20 for IERC20;

  //=======================================
  // Constants
  //=======================================
  uint256 public constant MAGIC_REFINERY_PROPERTY_LEVEL = 0;

  //=======================================
  // Immutables
  //=======================================
  IMagicRefinery public immutable REFINERY;
  IMagicRefineryData public immutable DATA;

  address public immutable VAULT;
  IERC20 public immutable TOKEN;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => uint256) public redeemAmounts;
  mapping(uint256 => uint256) public redeemedTokens;

  //=======================================
  // Events
  //=======================================
  event MagicRefineryCataclysmRedeemed(
    address structureAddress,
    uint256 structureId
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _refinery,
    address _refineryData,
    address _vault,
    address _tokenAddress,
    uint256[3] memory _tiers
  ) ManagerModifier(_manager) {
    REFINERY = IMagicRefinery(_refinery);
    DATA = IMagicRefineryData(_refineryData);
    VAULT = _vault;
    TOKEN = IERC20(_tokenAddress);

    redeemAmounts[0] = _tiers[0];
    redeemAmounts[1] = _tiers[1];
    redeemAmounts[2] = _tiers[2];
  }

  //=======================================
  // External
  //=======================================
  function redeem(uint256[] calldata _ids) external nonReentrant whenNotPaused {
    uint256 redeemedTotal;

    for (uint256 j = 0; j < _ids.length; j++) {
      uint256 structureId = _ids[j];

      // Check if refinery is already redeemed
      require(
        redeemedTokens[structureId] == 0,
        "MagicRefineryRedeem: Refinery already redeemed"
      );

      // Check sender owns refinery
      address owner = REFINERY.ownerOf(structureId);
      require(
        owner == msg.sender,
        "MagicRefineryRedeem: You do not own the Refinery"
      );

      // Get Refinery tier
      uint256 level = DATA.data(structureId, MAGIC_REFINERY_PROPERTY_LEVEL);

      // Should only work for Tier 1-3 (level 0-2) Refineries
      require(
        level < 3,
        "MagicRefineryRedeem: This refinery tier can't be redeemed"
      );

      // Collect amount redeemed from each refinery for final transfer later
      redeemedTotal += redeemAmounts[level];

      // Mark as redeemed
      redeemedTokens[structureId] = redeemAmounts[level];

      // Emit event
      emit MagicRefineryCataclysmRedeemed(address(REFINERY), structureId);
    }

    // Transfer $MAGIC
    TOKEN.safeTransferFrom(VAULT, msg.sender, redeemedTotal);
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
}

