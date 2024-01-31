// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721Tradable.sol";

/**
 * @title Creature
 * Creature - a contract for my non-fungible creatures.
 */
contract Creature is ERC721Tradable {
  constructor(address _proxyRegistryAddress, address _ownerOfTokens)
    ERC721Tradable("Big Board NFT", "BBNFT", _proxyRegistryAddress, _ownerOfTokens)
  {}

  function baseTokenURI() override public pure returns (string memory) {
    return "https://bigboardnft.com/api/tokens/";
  }
}

