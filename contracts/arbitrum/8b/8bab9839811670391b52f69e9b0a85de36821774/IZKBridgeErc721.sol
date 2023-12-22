// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IZKBridgeErc721 {

    function zkBridgeMint(address _to, uint256 _tokenId, string memory tokenURI_) external;

    function zkBridgeBurn(uint256 _tokenId) external;
}
