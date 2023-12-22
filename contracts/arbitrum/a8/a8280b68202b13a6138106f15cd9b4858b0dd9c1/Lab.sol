// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC1155.sol";
import "./ReentrancyGuard.sol";

import "./ManagerModifier.sol";
import "./ILab.sol";

contract Lab is ERC1155, ReentrancyGuard, ManagerModifier, ILab {
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
  ) external nonReentrant onlyMinter {
    _mint(_for, _id, _amount, "");
  }

  function mintBatchFor(
    address _for,
    uint256[] calldata _ids,
    uint256[] calldata _amounts
  ) external nonReentrant onlyMinter {
    _mintBatch(_for, _ids, _amounts, "");
  }

  function burnFor(
    address _for,
    uint256 _id,
    uint256 _amount
  ) external nonReentrant onlyMinter {
    _burn(_for, _id, _amount);
  }

  function burnBatchFor(
    address _for,
    uint256[] calldata _ids,
    uint256[] calldata _amounts
  ) external nonReentrant onlyMinter {
    _burnBatch(_for, _ids, _amounts);
  }

  function burn(uint256 _id, uint256 _amount) external nonReentrant {
    _burn(msg.sender, _id, _amount);
  }

  function burnBatch(
    uint256[] calldata ids,
    uint256[] calldata amounts
  ) external nonReentrant {
    _burnBatch(msg.sender, ids, amounts);
  }

  //=======================================
  // Admin
  //=======================================
  function setUri(string memory _uri) external onlyAdmin {
    _setURI(_uri);
  }
}

