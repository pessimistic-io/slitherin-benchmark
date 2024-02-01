// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

library Types {
  // Fixed-size order part with core information
  struct StaticOrder {
    uint256 salt;
    address makerAsset;
    address takerAsset;
    address maker;
    address receiver;
    address allowedSender; // equals to Zero address on public orders
    uint256 makingAmount;
    uint256 takingAmount;
  }

  // `StaticOrder` extension including variable-sized additional order meta information
  struct Order {
    uint256 salt;
    address makerAsset;
    address takerAsset;
    address maker; // contract address of the maker
    address receiver;
    address allowedSender; // equals to Zero address on public orders
    uint256 makingAmount;
    uint256 takingAmount;
    bytes makerAssetData;
    bytes takerAssetData;
    bytes getMakerAmount;
    bytes getTakerAmount;
    bytes predicate;
    bytes permit;
    bytes interaction;
  }
}

