// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./IERC20.sol";
import "./IERC721.sol";
import "./IERC1155.sol";
import "./SafeERC20.sol";
import "./ERC165.sol";

import "./ANFTReceiver2.sol";

import "./Diamond.sol";
import "./OwnershipFacet.sol";

contract ShiftSweeper is Diamond, ANFTReceiver2, OwnershipModifers {
  using SafeERC20 for IERC20;

  constructor(address _contractOwner, address _diamondCutFacet)
    Diamond(_contractOwner, _diamondCutFacet)
  {}
}

