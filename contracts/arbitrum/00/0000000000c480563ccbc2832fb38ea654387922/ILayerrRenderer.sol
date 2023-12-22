// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC165} from "./IERC165.sol";

/**
 * @title ILayerrRenderer
 * @author 0xth0mas (Layerr)
 * @notice ILayerrRenderer interface defines functions required in LayerrRenderer to be callable by token contracts
 */
interface ILayerrRenderer is ERC165 {

    enum RenderType {
        LAYERR_HOSTED,
        PREREVEAL,
        BASE_PLUS_TOKEN
    }

    /// @dev Thrown when a payment fails for Layerr-hosted IPFS
    error PaymentFailed();

    /// @dev Thrown when a call is made for an owner-function by a non-contract owner
    error NotContractOwner();

    /// @dev Thrown when a signature is not made by the authorized account
    error InvalidSignature();

    /**
     * @notice Generates a tokenURI for the `contractAddress` and `tokenId`
     * @param contractAddress token contract address to render a token URI for
     * @param tokenId token id to render
     * @return uri for the token metadata
     */
    function tokenURI(
        address contractAddress,
        uint256 tokenId
    ) external view returns (string memory);

    /**
     * @notice Generates a contractURI for the `contractAddress`
     * @param contractAddress contract address to render a contract URI for
     * @return uri for the contract metadata
     */
    function contractURI(
        address contractAddress
    ) external view returns (string memory);
}

