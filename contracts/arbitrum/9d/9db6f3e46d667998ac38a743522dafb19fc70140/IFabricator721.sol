// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;

import "./IMintValidator721.sol";

interface IFabricator721 {
  function modularMintInit(
    uint256 _dropId,
    address _to,
    bytes memory _data,
    address _validator,
    string calldata _metadata
  ) external;

  function modularMintCallback(
    address recipient,
    uint256 _id,
    bytes memory _data
  ) external;

  function quantityMinted(uint256 collectibleId) external returns (uint256);

  function idToValidator(uint256 collectibleId) external returns (address);
}

