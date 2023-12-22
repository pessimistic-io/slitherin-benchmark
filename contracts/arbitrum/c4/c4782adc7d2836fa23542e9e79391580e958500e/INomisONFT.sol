// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/**
 * @title INomisONFT.
 * @author Nomis team.
 * @notice Interface for Nomis ONFT contract.
 */
interface INomisONFT {
    /**
     * @notice Mint a new ONFT.
     * @dev Only the ONFT contract can call this function.
     * @param to The address of the new ONFT owner.
     * @param tokenId The minted token id. 
     * @param tokenURI_ The token URI of the minted token.
     */
    function mint(
        address to,
        uint256 tokenId,
        string memory tokenURI_
    ) external;
}

