// SPDX-License-Identifier: MIT LICENSE
pragma solidity 0.8.15;
import "./Ownable.sol";
import "./ERC721Enumerable.sol";
import "./ERC721Holder.sol";
import "./ERC721.sol";
import "./ECDSA.sol";
import "./draft-ERC20Permit.sol";
import "./Base64.sol";
import "./Strings.sol";
import "./CheeseHeroTypes.sol";

contract CheeseHeroURI is Ownable {
  using Strings for uint256;
  using ECDSA for bytes32;

  string[][8] public attributes;
  string[8] public attributeName;
  string public constant descriptionStatic = 'Cheese Hero fair launch on arbitrum blockchain. Cooking you cheese. Become a cheese master. Mint your cheese hero';

  string[5] public rarity = ['CHEESE', 'N', 'R', 'SR', 'SSR'];

  constructor() {
    for (uint256 i = 0; i < 8; i++) {
      attributes[i] = new string[](1);
    }
  }

  function tokenURI(uint256 id, CheeseHeroTypes.HeroTraits calldata meta) external view returns (string memory) {
    string memory name = bytes(meta.name).length > 0 ? meta.name : string(abi.encodePacked('CheeseHero #', id.toString()));
    string memory description = bytes(meta.description).length > 0 ? meta.description : descriptionStatic;
    string memory metadata = string(
      abi.encodePacked(
        // ...
        '{"name":"',
        name,
        '","description":"',
        description,
        '","image":"',
        meta.image,
        '", "attributes":',
        compileAttributes(meta),
        '}'
      )
    );
    return string(abi.encodePacked('data:application/json;base64,', Base64.encode(bytes(metadata))));
  }

  function setAttributes(uint8 index, string calldata name, string[] memory _attributes) external onlyOwner {
    attributes[index] = _attributes;
    attributeName[index] = name;
  }

  function attributeForTypeAndValue(string memory traitType, string memory value) internal pure returns (string memory) {
    if (bytes(value).length == 0) return '';
    return
      string(
        abi.encodePacked(
          // ..
          ',{"trait_type":"',
          traitType,
          '","value":"',
          value,
          '"}'
        )
      );
  }

  function compileAttributes(CheeseHeroTypes.HeroTraits calldata meta) public view returns (string memory) {
    string[8] memory names = attributeName;
    string[][8] memory attrs = attributes;
    uint32[8] memory traitValues;
    for (uint256 i = 0; i < 8; i++) {
      traitValues[i] = uint32((meta.attributes >> (i * 32)) & 0xffffffff);
    }

    string memory data = string(
      abi.encodePacked(
        attributeForTypeAndValue(names[0], attrs[0][traitValues[0]]),
        attributeForTypeAndValue(names[1], attrs[1][traitValues[1]]),
        attributeForTypeAndValue(names[2], attrs[2][traitValues[2]]),
        attributeForTypeAndValue(names[3], attrs[3][traitValues[3]]),
        abi.encodePacked(
          attributeForTypeAndValue(names[4], attrs[4][traitValues[4]]),
          attributeForTypeAndValue(names[5], attrs[5][traitValues[5]]),
          attributeForTypeAndValue(names[6], attrs[6][traitValues[6]]),
          attributeForTypeAndValue(names[7], attrs[7][traitValues[7]])
        )
      )
    );

    return
      string(
        abi.encodePacked(
          // ..
          '[{"trait_type":"RARE","value":"',
          rarity[uint256(meta.rarity)],
          '"}',
          data,
          ']'
        )
      );
  }

  function getAttributes(uint8 index) external view returns (string[] memory) {
    return attributes[index];
  }

  function getAttributeName() external view returns (string[8] memory) {
    return attributeName;
  }
}

