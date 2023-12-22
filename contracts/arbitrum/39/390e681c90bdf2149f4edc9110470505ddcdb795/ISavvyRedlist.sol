// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

interface ISavvyRedlist {
    /// @notice Emitted when the allowlist contract is updated.
    ///
    /// @param allowlist_ The address of the allowlist contract.
    event AllowlistUpdated(address indexed allowlist_);

    /// @notice Emitted when the protocol token required flag is updated.
    ///
    /// @param protocolTokenRequired_ The protocol token required flag.
    event ProtocolTokenRequired(bool indexed protocolTokenRequired_);

    /// @notice Emitted when an NFT collection is added.
    ///
    /// @param nftCollection_ The address of the NFT collection.
    event NFTCollectionAdded(address indexed nftCollection_);

    /// @notice Emitted when an NFT collection is removed.
    ///
    /// @param nftCollection_ The address of the NFT collection.
    event NFTCollectionRemoved(address indexed nftCollection_);

    /// @notice Set the address of the allowlist contract.
    /// @notice Emits a {AllowlistUpdated} event.
    /// @dev `msg.sender` must be owner.
    /// @param allowlist_ The address of the allowlist contract.
    function setAllowlist(address allowlist_) external;

    /// @notice Set the protocol token required flag.
    /// @notice Emits a {ProtocolTokenRequired} event.
    /// @dev `msg.sender` must be owner.
    /// @param protocolTokenRequired_ The protocol token required flag.
    function setProtocolTokenRequired(bool protocolTokenRequired_) external;

    /// @notice Get all the NFT collection addresses.
    /// @return nftCollections_ The array of NFT collection addresses.
    function getNFTCollections() external view returns (address[] memory);

    /// @notice Check if an NFT collection is eligible for redlist.
    /// @param nftCollection_ The address of the NFT collection.
    /// @return isRedlistNFT_ True if the NFT collection is eligible for redlist.
    function isRedlistNFT(address nftCollection_) external view returns (bool);

    /// @notice Add an NFT collection to the eligible redlist.
    /// @notice Emits a {NFTCollectionAdded} event.
    /// @dev `msg.sender` must be owner.
    /// @param nftCollection_ The address of the NFT collection.
    function addNFTCollection(address nftCollection_) external;

    /// @notice Remove an NFT collection from the eligible redlist.
    /// @notice Emits a {NFTCollectionRemoved} event.
    /// @dev `msg.sender` must be owner.
    /// @param nftCollection_ The address of the NFT collection.
    function removeNFTCollection(address nftCollection_) external;

    /// @notice Check if an account is redlisted.
    /// @dev This function is not view because it updates the cache.
    /// @param account_ The address of the account.
    /// @param isProtocolTokenRequire_ The status that require protocol token or not.
    /// @param eligibleNFTRequire_ The status that require eligible NFT or not.
    /// @return isRedlisted_ True if the account is redlisted.
    function isRedlisted(
        address account_,
        bool eligibleNFTRequire_,
        bool isProtocolTokenRequire_
    ) external returns (bool);
}

