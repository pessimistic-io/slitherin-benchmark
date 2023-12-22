// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IERC721.sol";

interface IAsset is IERC721 {
  function batchMint(address to, uint256[] memory tokenIds) external;
}

