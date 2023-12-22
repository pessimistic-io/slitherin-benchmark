// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./strings.sol";
import "./console.sol";

//==================================================
// Utility functions to generate ERC token metadata
//==================================================

library metadata {
  function convertToMetadata(
    string memory collectionName,
    string memory collectionDescription,
    string memory imageUrl,
    string[] memory attributeKeys,
    string[] memory attributeValues
  ) internal pure returns (string memory) {
    return
      string.concat(
        'data:application/json;utf8,{"name":"',
        collectionName,
        '","description":"',
        collectionDescription,
        '", "image":"',
        imageUrl,
        '","attributes":',
        convertToAttributes(attributeKeys, attributeValues),
        "}"
      );
  }

  string constant JSON_TRAIT_START = '{"trait_type":"';
  string constant JSON_TRAIT_MID = '","value":"';
  string constant JSON_TRAIT_END = '"}';

  function convertToAttributes(
    string[] memory attributeKeys,
    string[] memory attributeValues
  ) internal pure returns (string memory) {
    return
      strings.buildJsonKeyMapArray(
        JSON_TRAIT_START,
        JSON_TRAIT_MID,
        JSON_TRAIT_END,
        attributeKeys,
        attributeValues
      );
  }
}

