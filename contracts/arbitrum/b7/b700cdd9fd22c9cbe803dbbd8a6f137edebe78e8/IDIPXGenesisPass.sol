// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IERC721.sol";

interface IDIPXGenesisPass is IERC721{
  function tokenOfOwner(address owner) external view returns(uint256[] memory);
  function safeMint(address to,uint256 tokenId) external;
}

