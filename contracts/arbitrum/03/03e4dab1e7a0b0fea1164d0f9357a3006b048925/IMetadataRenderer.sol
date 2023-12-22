// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IMetadataRenderer {
  function contractURI(
    string calldata name,
    string calldata description,
    string calldata imageURL,
    string calldata externalLink,
    uint16 bps,
    address contractAddress
  ) external pure returns (string memory);

  function tokenURI(uint256) external view returns (string memory);

  function initializeWithData(bytes memory initData) external;
}

