// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC1155.sol";
import "./ReentrancyGuard.sol";

import "./ManagerModifier.sol";
import "./IERC721Bound.sol";
import "./ILootBoxMetadata.sol";

contract LootBox is ERC1155, ReentrancyGuard, ManagerModifier {
  ILootBoxMetadata public metadata;

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _metadata
  ) ERC1155("") ManagerModifier(_manager) {
    metadata = ILootBoxMetadata(_metadata);
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

  function safeBurnBatch(
    address _for,
    uint256[] memory ids,
    uint256[] memory amounts
  ) external nonReentrant {
    require(
      _for == msg.sender || isApprovedForAll(_for, msg.sender),
      "ERC1155: caller is not owner nor approved"
    );

    _burnBatch(_for, ids, amounts);
  }

  function getMetadata(uint256 _tokenId) public view returns (string memory) {
    return metadata.getMetadata(_tokenId);
  }

  function _beforeTokenTransfer(
    address operator,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  ) internal override {
    if (from == address(0) || to == address(0)) {
      return;
    }

    for (uint256 i = 0; i < ids.length; i++) {
      require(metadata.isBound(ids[i]) == false, "Token Bind Error");
    }
  }

  //=======================================
  // Admin
  //=======================================
  function setUri(string memory _uri) external onlyAdmin {
    _setURI(_uri);
  }

  function updateMetadata(address _addr) external onlyAdmin {
    metadata = ILootBoxMetadata(_addr);
  }
}

