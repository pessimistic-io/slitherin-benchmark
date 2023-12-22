// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./IRoyaltyManager.sol";

/**
 * @notice Core creation interface
 * @author highlight.xyz
 */
interface IERC721Editions {
    /**
     * @notice Create an edition
     * @param _editionInfo Encoded edition metadata
     * @param _editionSize Edition size
     * @param _editionTokenManager Token manager for edition
     * @param editionRoyalty Edition's royalty
     * @param mintVectorData Mint vector data
     */
    function createEdition(
        bytes memory _editionInfo,
        uint256 _editionSize,
        address _editionTokenManager,
        IRoyaltyManager.Royalty memory editionRoyalty,
        bytes calldata mintVectorData
    ) external returns (uint256);

    /**
     * @notice Get the first token minted for each edition passed in
     */
    function getEditionStartIds() external view returns (uint256[] memory);
}

