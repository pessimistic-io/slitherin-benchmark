// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMagicDomainRegistrar {
    event NameRegistered(uint256 indexed id, address indexed owner);
    event NameRemoved(uint256 indexed id, address indexed owner);
    event BaseURIChanged(string from, string to);

    struct SubdomainMetadata {
        string name;
        string discriminant;
    }

    // Set the resolver for the TLD this registrar manages.
    function setResolver(address resolver) external;

    // Returns true iff the specified name is available for registration.
    function available(uint256 id) external view returns(bool);

    /**
     * @dev Register a node by semi unique name & discriminant.
     * @param name The semi unique name to register.
     * @param discriminant The discriminant to make the name unique.
     * @param owner The address that should own the new name.
     */
    function register(string memory name, string memory discriminant, address owner) external;

    /**
     * @dev Exchanges the owner's current name for a new one.
     * @param newName The new semi unique name.
     * @param discriminant The discriminant to make the name unique.
     * @param owner The address that should own the new name.
     */
    function changeName(string memory newName, string memory discriminant, address owner) external;

    /**
     * @dev Reclaim ownership of a node in ENS, if you own it in the registrar.
     */
    function reclaim(string memory name, string memory discriminant, address owner) external;

    /**
     * @dev Converts a semi unique name with its discriminant into a tokenId.
     * @param name The semi unique name.
     * @param discriminant The discriminant to make the name unique.
     */
    function tagToId(string memory name, string memory discriminant) external pure returns(uint256 tokenId_);
}

