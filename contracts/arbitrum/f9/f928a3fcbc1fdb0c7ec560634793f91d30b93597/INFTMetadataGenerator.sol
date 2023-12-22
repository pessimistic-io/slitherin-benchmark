// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./ISmartVault.sol";

interface INFTMetadataGenerator {
    function generateNFTMetadata(uint256 _tokenId, ISmartVault.Status memory _vaultStatus) external pure returns (string memory);
}
