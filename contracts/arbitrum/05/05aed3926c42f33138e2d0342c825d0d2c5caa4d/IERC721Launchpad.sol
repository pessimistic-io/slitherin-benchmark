// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20.sol";

interface IERC721Launchpad {
  struct SignMintParams {
    uint256 mintSessionId;
    uint256 mintSessionLimit;
    uint256 walletMintSessionLimit;
    uint256 fee;
    IERC20 feeErc20Address;
    string tokenIdentify;
  }
}
