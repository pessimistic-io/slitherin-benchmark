// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC1155.sol";
import "./ReentrancyGuard.sol";

import "./ManagerModifier.sol";

contract Material is ERC1155, ReentrancyGuard, ManagerModifier {
  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ERC1155("") ManagerModifier(_manager) {
    UNBOUND = false;
  }

  bool public UNBOUND;

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

  function _beforeTokenTransfer(
    address operator,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  ) internal view override {
    if (from == address(0) || to == address(0)) {
      return;
    }

    require(UNBOUND, "Material: Token not unbound");
  }

  //=======================================
  // Admin
  //=======================================
  function setUri(string memory _uri) external onlyAdmin {
    _setURI(_uri);
  }

  function bind() external onlyAdmin {
    UNBOUND = false;
  }

  function unbind() external onlyAdmin {
    UNBOUND = true;
  }
}

