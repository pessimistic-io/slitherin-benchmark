// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC1155.sol";
import "./ReentrancyGuard.sol";

import "./ManagerModifier.sol";

contract Collectible is ERC1155, ReentrancyGuard, ManagerModifier {
  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ERC1155("") ManagerModifier(_manager) {}

  //=======================================
  // External
  //=======================================
  function mintFor(
    address _for,
    uint256 _id,
    uint256 _amount
  ) external payable nonReentrant onlyMinter {
    _mint(_for, _id, _amount, "");
  }

  function mintBatchFor(
    address _for,
    uint256[] memory _ids,
    uint256[] memory _amounts
  ) external payable nonReentrant onlyMinter {
    _mintBatch(_for, _ids, _amounts, "");
  }

  function burn(uint256 _id, uint256 _amount) external nonReentrant {
    _burn(msg.sender, _id, _amount);
  }

  function burnBatch(uint256[] memory ids, uint256[] memory amounts)
    external
    nonReentrant
  {
    _burnBatch(msg.sender, ids, amounts);
  }

  //=======================================
  // Admin
  //=======================================
  function setUri(string memory _uri) external onlyAdmin {
    _setURI(_uri);
  }
}

