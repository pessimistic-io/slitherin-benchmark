// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721PresetMinterPauserAutoId.sol";

contract DiamondPepes is ERC721PresetMinterPauserAutoId('Diamond Pepes', 'DP', 'ipfs://QmWbZSdNSNa5JCMoEbj75gtACBDcv5dFfaq6sZRD1uZ4jH/') {
  constructor() {
    // Mint 50 NFTs
    for (uint i = 0; i < 50; i++)
      mint(msg.sender);
  }
}
