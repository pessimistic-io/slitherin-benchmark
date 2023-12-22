// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

interface FractionTreasuryInterface {
  function getFractionToken() external view returns (address fractionToken);

  function getSourceERC20() external view returns (address sourceERC20);

  function getSourceERC721() external view returns (address sourceERC721);

  function setFractionToken(address fractionToken) external;

  function setSourceERC20(address sourceERC20) external;

  function setSourceERC721(address sourceERC721) external;
}

