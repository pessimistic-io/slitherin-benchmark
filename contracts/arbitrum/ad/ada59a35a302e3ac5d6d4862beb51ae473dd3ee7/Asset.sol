// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./AssetType.sol";

struct Asset {
  AssetType assetType;
  address assetAddress; // 0x0 for ETH, the ERC20 address.  If it's an account balance, this could represent the token of the account
}

