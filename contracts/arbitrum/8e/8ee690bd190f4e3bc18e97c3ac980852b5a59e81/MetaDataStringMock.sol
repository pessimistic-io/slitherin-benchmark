pragma solidity ^0.8.0;

contract MetaDataStringMock {
  function getMetadataString(uint256 id) external view returns (string memory) {
    return "{'trait_type': 'Personality', 'value': 'Sad'}";
  }
}

