// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./ERC721Holder.sol";
import "./CollectionManager.sol";

contract CharacterManager is CollectionManager {

// STATE VARIABLES
   
    /// @dev A permanent mapping to track the the underlying collection & token to a hash of the collection address & wrappedTokenID
    /// @dev Hash of (collection & wrappedTokenID) >> WrappedToken(collection, wrappedTokenID)
    mapping (bytes32 => WrappedToken) public wrappedToken;

    /// @dev A mapping to track the wrapped token to the underlying collection & token
    /// @dev tokenID >> hash of the WrappedToken
    mapping (uint256 => bytes32) public wrappedTokenHashByID;

    /// @dev Maps the underlying token hash to the token id
    /// @dev Hash >> tokenID of the wrapped character
    mapping (bytes32 => uint256) public tokenIDByHash;
    
// EVENTS

    event Wrapped(address indexed account, address indexed collection, uint256 blockNumber, uint256 wrappedTokenID, uint256 tokenID, bytes32 wrappedTokenHash);
    event Unwrapped(address indexed account, address indexed collection, uint256 blockNumber, uint256 wrappedTokenID, uint256 tokenID, bytes32 wrappedTokenHash);

// FUNCTIONS

    /// @dev PUBLIC: Add an NFT to the contract
    /// @param collectionAddress the address of the collection
    /// @param wrappedTokenID the id of the NFT to wrap
    /// @param tokenID Characters ID
    function _wrap(address account, address collectionAddress, uint256 wrappedTokenID, uint256 tokenID)
        internal
        isRegistered(collectionAddress)
    {
        // Calculate the underlying token hash
        bytes32 wrappedTokenHash = hashWrappedToken(collectionAddress, wrappedTokenID);
        // If this character has not been wrapped previously then
        if (isNeverWrapped(collectionAddress, wrappedTokenID)) {
            // Add Collection address to the mapping
            wrappedToken[wrappedTokenHash].collectionAddress = collectionAddress;
            // Add Underlying Token ID to the mapping
            wrappedToken[wrappedTokenHash].wrappedTokenID = wrappedTokenID;
            // Map the wrapped token id to underlying token hash
            wrappedTokenHashByID[tokenID] = wrappedTokenHash;
            // Map the underlying token hash to the wrapped token id
            tokenIDByHash[wrappedTokenHash] = tokenID;
        }
        // Flag status as wrapped
        wrappedToken[wrappedTokenHash].status = WrappedStatus.Wrapped;
        // Write an event
        emit Wrapped(account, collectionAddress, block.number, wrappedTokenID, tokenID, wrappedTokenHash);
        // Transfer character to contract
        IERC721(collectionAddress).safeTransferFrom(account, address(this), wrappedTokenID);
    }

    /// @dev PUBLIC: Release an NFT from the contract
    /// @dev Relies on the Owner check being completed when the wrapped token is burned
    /// @param tokenID the id of the NFT to release
    function _unwrap(uint256 tokenID)
        internal
    {
        (address collectionAddress, uint256 wrappedTokenID, WrappedStatus status) = getWrappedTokenDetails(tokenID);
        // Ensure token is wrapped
        require(status == WrappedStatus.Wrapped, "There is no token to unwrap");
        // Calculate the underlying token hash
        bytes32 wrappedTokenHash = hashWrappedToken(collectionAddress, wrappedTokenID);
        // Flag status as unwrapped
        wrappedToken[wrappedTokenHash].status = WrappedStatus.Unwrapped;
        // Write an event
        emit Unwrapped(_msgSender(), collectionAddress, block.number, wrappedTokenID, tokenID, wrappedTokenHash);
        // Return Item to owner
        IERC721(collectionAddress).safeTransferFrom(address(this), _msgSender(), wrappedTokenID);
    }

// VIEW FUNCTIONS

    /// @dev Check mapping for wrapped character underlying token details
    /// @param tokenID Characters ID
    function getWrappedTokenDetails(uint256 tokenID)
        public
        view
        returns (
            address collectionAddress,
            uint256 wrappedTokenID,
            WrappedStatus status
            )
    {
        return (wrappedToken[wrappedTokenHashByID[tokenID]].collectionAddress,
                wrappedToken[wrappedTokenHashByID[tokenID]].wrappedTokenID,
                wrappedToken[wrappedTokenHashByID[tokenID]].status
                );
    }

    /// @dev Check if a token is wrapped
    /// @param collectionAddress the address of the collection
    /// @param wrappedTokenID the id of the NFT to release
    function isWrapped(address collectionAddress, uint256 wrappedTokenID)
        external
        view
        returns (
            bool tokenIsWrapped
            )
    {
        if (wrappedToken[hashWrappedToken(collectionAddress, wrappedTokenID)].status == WrappedStatus.Wrapped) {
            return (true);
        }
    }

    /// @dev Check if a token is wrapped
    /// @param collectionAddress the address of the collection
    /// @param wrappedTokenID the id of the NFT to release
    function isNeverWrapped(address collectionAddress, uint256 wrappedTokenID)
        public
        view
        returns (
            bool tokenNeverWrapped
            )
    {
        if (wrappedToken[hashWrappedToken(collectionAddress, wrappedTokenID)].status == WrappedStatus.NeverWrapped) {
            return (true);
        }
    }

    /// @dev Hash the underlying collection details
    /// @param collectionAddress the address of the collection
    /// @param wrappedTokenID the id of the NFT to release
    function hashWrappedToken(address collectionAddress, uint256 wrappedTokenID)
       public
       pure
       returns (
           bytes32 wrappedTokenHash
            )
    {
        wrappedTokenHash = keccak256(abi.encodePacked(collectionAddress, wrappedTokenID));
    }

}
