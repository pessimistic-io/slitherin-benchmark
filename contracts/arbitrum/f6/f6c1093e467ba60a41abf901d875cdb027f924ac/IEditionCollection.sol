// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

/**
 * @notice Interfaces with the details of editions on collections
 * @author highlight.xyz
 */
interface IEditionCollection {
    /**
     * @notice Edition details
     * @param name Edition name
     * @param size Edition size
     * @param supply Total number of tokens minted on edition
     * @param initialTokenId Token id of first token minted in edition
     */
    struct EditionDetails {
        string name;
        uint256 size;
        uint256 supply;
        uint256 initialTokenId;
    }

    /**
     * @notice Get the edition a token belongs to
     * @param tokenId The token id of the token
     */
    function getEditionId(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Get an edition's details
     * @param editionId Edition id
     */
    function getEditionDetails(uint256 editionId) external view returns (EditionDetails memory);

    /**
     * @notice Get the details and uris of a number of editions
     * @param editionIds List of editions to get info for
     */
    function getEditionsDetailsAndUri(uint256[] calldata editionIds)
        external
        view
        returns (EditionDetails[] memory, string[] memory uris);
}

