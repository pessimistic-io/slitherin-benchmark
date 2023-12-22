// SPDX-License-Identifier: MIT
// This is a Smart Contract written in Solidity. It represents a vault that allows users to deposit WETH and receive DPXV in return. The contract uses the functionalities of other smart contracts such as oneInch aggregator, SushiSwap, and MiniChefV2 to perform swaps and farming of SUSHI and DPX tokens. The contract has several functions including deposit(), redeem(), claim(), totalAssets(), totalLockedAssets(), totalStakedButWithoutLockedAssets(), and getClaimableRewards().

pragma solidity 0.8.18;

import "./BaseSushiSwapVault.sol";

contract MagicArbitrumVault is BaseSushiSwapVault {
  constructor(
    IERC20Metadata asset_,
    string memory name_,
    string memory symbol_
  ) BaseSushiSwapVault(asset_, name_, symbol_) {
    _initializePid(13);
    _initializeLpTokenAndRewarder(
      0x539bdE0d7Dbd336b79148AA742883198BBF60342,
      0x1a9c20e2b0aC11EBECbDCA626BBA566c4ce8e606
    );
  }
}

