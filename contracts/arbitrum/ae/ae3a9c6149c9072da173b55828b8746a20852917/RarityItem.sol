// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import "./ERC1155.sol";
import "./ReentrancyGuard.sol";

import "./ManagerModifier.sol";
import "./IRarityItemMetadata.sol";

contract RarityItem is ERC1155, ReentrancyGuard, ManagerModifier {
  //=======================================
  // Interfaces
  //=======================================
  IRarityItemMetadata public metadata;

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _metadata
  ) ERC1155("") ManagerModifier(_manager) {
    metadata = IRarityItemMetadata(_metadata);
  }

  //=======================================
  // External
  //=======================================
  function mintFor(
    address _for,
    uint256 _id,
    uint256 _amount
  ) external nonReentrant onlyMinter {
    _mint(_for, _id, _amount, "");
  }

  function mintBatchFor(
    address _for,
    uint256[] memory _ids,
    uint256[] memory _amounts
  ) external nonReentrant onlyMinter {
    _mintBatch(_for, _ids, _amounts, "");
  }

  function burn(uint256 _id, uint256 _amount) external nonReentrant {
    _burn(msg.sender, _id, _amount);
  }

  function burnBatch(
    uint256[] memory ids,
    uint256[] memory amounts
  ) external nonReentrant {
    _burnBatch(msg.sender, ids, amounts);
  }

  function uri(uint256 _tokenId) public view override returns (string memory) {
    return metadata.getMetadata(_tokenId);
  }

  //=======================================
  // Admin
  //=======================================

  function updateMetadata(address _addr) external onlyAdmin {
    metadata = IRarityItemMetadata(_addr);
  }
}

