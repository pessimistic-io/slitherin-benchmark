// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import "./IRarityItemCharacteristicDefinitions.sol";

interface IRarityItemMinter {
  function mintRandom(
    uint16 _rarity,
    uint256 _randomBase,
    address _recipient
  ) external returns (uint256, uint256, address);

  event RarityItemMinted(
    uint256 _tokenId,
    string _name,
    address _recipient,
    uint256 _count
  );
}

