// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface INFTMetadata {
    /// @dev Function to extend the `contractURI()` function
    /// @notice Intended to be invoked in the context of a delegatecall
    function ext_contractURI() external view returns (string memory uri);

    /// @dev Function to extend the `tokenURI()` function
    /// @notice Intended to be invoked in the context of a delegatecall
    function ext_tokenURI(uint256 tokenId) external view returns (string memory uri);
}

