// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IGeNftDescriptor {
  struct ConstructTokenURIParams {
    uint256 tokenId;
    address quoteTokenAddress;
    address baseTokenAddress;
    string quoteTokenSymbol;
    string baseTokenSymbol;
    bool isCall;
    int pnl;
  }

  function constructTokenURI(ConstructTokenURIParams memory params) external view returns (string memory uri);
}
