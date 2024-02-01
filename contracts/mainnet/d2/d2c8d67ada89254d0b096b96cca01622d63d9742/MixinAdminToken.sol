// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract MixinAdminToken {
  // admin address to tokenId map
  mapping(address => uint256) private _tokenIdByAdmin;

  function _saveAdminTokenId(address to, uint tokenId) internal {
    _tokenIdByAdmin[to] = tokenId;
  }

  function tokenIdByAdmin(address admin) internal view returns (uint256) {
    return _tokenIdByAdmin[admin];
  }
}

