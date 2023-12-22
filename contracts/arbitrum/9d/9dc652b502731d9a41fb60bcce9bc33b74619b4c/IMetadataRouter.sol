// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMetadataRouter {
    // events
    event DefaultURIUpdated(string uri);
    event RouteURIUpdated(string route, string uri);
    event ContractRouteURIUpdated(string route, string uri, address indexed contractAddress);

    /// @dev Get the base URI for a specific route and contract address.
    /// @param route The name of the route.
    /// @param contractAddress The address of the contract for which to request a URI.
    /// @return '' The base URI for the specified route and contract address.
    /// @notice If a route-specific URI is not configured for the contract address, the default URI will be used.
    function baseURI(string memory route, address contractAddress) external view returns (string memory);

    /// @dev Get the default URI for cases where no specific URI is configured.
    /// @return '' The default URI.
    function defaultURI() external view returns (string memory);

    /// @dev Get the URI for the MetadataRouter contract itself.
    /// @return uri The URI for the MetadataRouter contract.
    function contractURI() external view returns (string memory uri);

    /// @dev Get the URI configured for a specific route.
    /// @param route The name of the route.
    /// @return uri The URI configured for the specified route.
    function routeURI(string memory route) external view returns (string memory);

    /// @dev Get the URI configured for a specific route and contract address.
    /// @param route The name of the route.
    /// @param contractAddress The address of the contract for which to request a URI.
    /// @return '' The URI configured for the specified route and contract address.
    function contractRouteURI(string memory route, address contractAddress) external view returns (string memory);

    /// @dev Get the full URI for a specific route and contract address.
    /// @param route The name of the route.
    /// @param contractAddress The address of the contract for which to request a URI.
    /// @return '' The full URI for the specified route and contract address.
    function uriOf(string memory route, address contractAddress) external view returns (string memory);

    /// @dev Get the full URI for a specific route and contract address, with additional appended data.
    /// @param route The name of the route.
    /// @param contractAddress The address of the contract for which the URI is requested.
    /// @param appendData Additional data to append to the URI.
    /// @return '' The full URI with appended data for the specified route and contract address.
    function uriOf(string memory route, address contractAddress, string memory appendData)
        external
        view
        returns (string memory);

    /// @dev Get the token URI for an NFT tokenId within a specific collection.
    /// @param collection The address of the NFT collection contract.
    /// @param tokenId The ID of the NFT token within the collection.
    /// @return '' The token URI for the specified NFT token.
    function tokenURI(address collection, uint256 tokenId) external view returns (string memory);

    /// @dev Set the default URI to be used when no specific URI is configured.
    /// @param uri The new default URI.
    /// @notice Only the contract owner can set the default URI.
    function setDefaultURI(string memory uri) external;

    /// @dev Set the URI for a specific route.
    /// @param uri The new URI to be configured for the route.
    /// @param route The name of the route.
    /// @notice Only the contract owner can set route-specific URIs.
    function setRouteURI(string memory uri, string memory route) external;

    /// @dev Set the URI for a specific route and contract address.
    /// @param uri The new URI to be configured for the route and contract address.
    /// @param route The name of the route.
    /// @param contractAddress The address of the contract for which the URI is configured.
    /// @notice Only the contract owner can set contract-specific URIs.
    function setContractRouteURI(string memory uri, string memory route, address contractAddress) external;
}

