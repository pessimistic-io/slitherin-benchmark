//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

uint8 constant TT_ERC20 = 1;
uint8 constant TT_ERC721 = 2;
uint8 constant TT_ERC1155 = 3;

struct ContractMeta {
  address addr;
  bool active;
  uint8 tokenType;
}

struct UserToken {
  uint contractId;
  uint tokenId;
}
