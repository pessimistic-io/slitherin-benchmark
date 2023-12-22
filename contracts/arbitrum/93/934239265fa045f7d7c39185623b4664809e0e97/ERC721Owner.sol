// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IERC721.sol";

contract ERC721Owner {
  //=======================================
  // Constructor
  //=======================================
  constructor() {}

  //=======================================
  // External
  //=======================================
  function walletOfOwner(
    uint256 _supply,
    address _contract,
    address _address
  ) external view returns (uint256[] memory) {
    uint256 _balance = IERC721(_contract).balanceOf(_address);
    uint256[] memory _tokens = new uint256[](_balance);
    uint256 _addedTokens;

    for (uint256 i = 0; i < _supply; i++) {
      try IERC721(_contract).ownerOf(i) returns (address _addr) {
        if (_addr != address(0) && _addr == _address) {
          _tokens[_addedTokens] = i;
          _addedTokens++;
        }
      } catch {}

      if (_addedTokens == _balance) break;
    }
    return _tokens;
  }
}

