// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

struct Purchase {
    uint256 usdcAmount;
    uint256 tokenAmount;
}

interface IPurchaser {
  function Purchase(uint256 usdcAmount) external returns (Purchase memory);
}


