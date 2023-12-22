// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./OwnableUpgradeable.sol";
import "./ERC2981Upgradeable.sol";
import "./ERC721URIStorageUpgradeable.sol";
import "./Counters.sol";
import "./IOperatorFilterRegistry.sol";

import "./MintpegErrors.sol";

/// @title Mintpeg Contract
/// @author Trader Joe
/// @notice ERC721 contracts for artists to mint NFTs
contract Mintpeg is
    ERC721URIStorageUpgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable
{
    using Counters for Counters.Counter;

    /// @notice Contract filtering allowed operators, preventing unauthorized contract to transfer NFTs
    /// By default, Mintpeg contracts are subscribed to OpenSea's Curated Subscription Address at 0x3cc6CddA760b79bAfa08dF41ECFA224f810dCeB6
    IOperatorFilterRegistry public operatorFilterRegistry;

    Counters.Counter private _tokenIds;

    /// @notice Emmited on setRoyaltyInfo()
    /// @param royaltyReceiver Royalty fee collector
    /// @param feePercent Royalty fee numerator; denominator is 10,000. So 500 represents 5%
    event RoyaltyInfoChanged(
        address indexed royaltyReceiver,
        uint96 feePercent
    );

    /// @notice Emmited on setTokenRoyaltyInfo()
    /// @param tokenId Token ID royalty to be set
    /// @param royaltyReceiver Royalty fee collector
    /// @param feePercent Royalty fee numerator; denominator is 10,000. So 500 represents 5%
    event TokenRoyaltyInfoChanged(
        uint256 tokenId,
        address indexed royaltyReceiver,
        uint96 feePercent
    );

    /// @notice Emmited on initialize()
    /// @param _collectionName ERC721 name
    /// @param _collectionSymbol ERC721 symbol
    /// @param _projectOwner function caller
    /// @param _royaltyReceiver Royalty fee collector
    /// @param _feePercent Royalty fee numerator; denominator is 10,000. So 500 represents 5%
    event InitializedMintpeg(
        string indexed _collectionName,
        string indexed _collectionSymbol,
        address indexed _projectOwner,
        address _royaltyReceiver,
        uint96 _feePercent
    );

    /// @dev Emitted on updateOperatorFilterRegistryAddress()
    /// @param operatorFilterRegistry New operator filter registry
    event OperatorFilterRegistryUpdated(
        IOperatorFilterRegistry indexed operatorFilterRegistry
    );

    /// @notice Allow spending tokens from addresses with balance
    /// Note that this still allows listings and marketplaces with escrow to transfer tokens if transferred
    /// from an EOA.
    modifier onlyAllowedOperator(address from) virtual {
        if (from != msg.sender) {
            _checkFilterOperator(msg.sender);
        }
        _;
    }

    /// @notice Allow approving tokens transfers
    modifier onlyAllowedOperatorApproval(address operator) virtual {
        _checkFilterOperator(operator);
        _;
    }

    /// @notice Mintpeg initialization
    /// @param _collectionName ERC721 name
    /// @param _collectionSymbol ERC721 symbol
    /// @param _royaltyReceiver Royalty fee collector
    /// @param _feePercent Royalty fee numerator; denominator is 10,000. So 500 represents 5%
    function initialize(
        string memory _collectionName,
        string memory _collectionSymbol,
        address _projectOwner,
        address _royaltyReceiver,
        uint96 _feePercent
    ) external initializer {
        __Ownable_init();
        __ERC2981_init();
        __ERC721_init(_collectionName, _collectionSymbol);
        setRoyaltyInfo(_royaltyReceiver, _feePercent);
        transferOwnership(_projectOwner);

        // Initialize the operator filter registry and subcribe to OpenSea's list
        IOperatorFilterRegistry _operatorFilterRegistry = IOperatorFilterRegistry(
                0x000000000000AAeB6D7670E522A718067333cd4E
            );
        if (address(_operatorFilterRegistry).code.length > 0) {
            _operatorFilterRegistry.registerAndSubscribe(
                address(this),
                0x3cc6CddA760b79bAfa08dF41ECFA224f810dCeB6
            );
        }
        _updateOperatorFilterRegistryAddress(_operatorFilterRegistry);

        emit InitializedMintpeg(
            _collectionName,
            _collectionSymbol,
            msg.sender,
            _royaltyReceiver,
            _feePercent
        );
    }

    /// @notice Function to mint new tokens
    /// @dev Can only be called by project owner
    /// @param _tokenURIs Array of tokenURIs (probably IPFS) of the tokenIds to be minted
    function mint(string[] memory _tokenURIs) external onlyOwner {
        uint256 newTokenId;
        for (uint256 i = 0; i < _tokenURIs.length; i++) {
            newTokenId = _tokenIds.current();
            _tokenIds.increment();
            _mint(msg.sender, newTokenId);
            _setTokenURI(newTokenId, _tokenURIs[i]);
        }
    }

    /// @notice Function for changing royalty information
    /// @dev Can only be called by project owner
    /// @dev owner can prevent any sale by setting the address to any address that can't receive AVAX.
    /// @param _royaltyReceiver Royalty fee collector
    /// @param _feePercent Royalty fee numerator; denominator is 10,000. So 500 represents 5%
    function setRoyaltyInfo(address _royaltyReceiver, uint96 _feePercent)
        public
        onlyOwner
    {
        // Royalty fees are limited to 25%
        if (_feePercent > 2_500) {
            revert Mintpeg__InvalidRoyaltyInfo();
        }
        _setDefaultRoyalty(_royaltyReceiver, _feePercent);
        emit RoyaltyInfoChanged(_royaltyReceiver, _feePercent);
    }

    /// @notice Function for changing token royalty information
    /// @dev Can only be called by project owner
    /// @dev owner can prevent any sale by setting the address to any address that can't receive AVAX.
    /// @param _tokenId Token ID royalty to be set
    /// @param _royaltyReceiver Royalty fee collector
    /// @param _feePercent Royalty fee numerator; denominator is 10,000. So 500 represents 5%
    function setTokenRoyaltyInfo(
        uint256 _tokenId,
        address _royaltyReceiver,
        uint96 _feePercent
    ) public onlyOwner {
        // Royalty fees are limited to 25%
        if (_feePercent > 2_500) {
            revert Mintpeg__InvalidRoyaltyInfo();
        }
        _setTokenRoyalty(_tokenId, _royaltyReceiver, _feePercent);
        emit TokenRoyaltyInfoChanged(_tokenId, _royaltyReceiver, _feePercent);
    }

    /// @notice Function for changing individual token URI
    /// @dev Can only be called by project owner
    /// @param _tokenId Token ID that will have URI changed
    /// @param _tokenURI Token URI to change to
    function setTokenURI(uint256 _tokenId, string memory _tokenURI)
        public
        onlyOwner
    {
        _setTokenURI(_tokenId, _tokenURI);
    }

    /// @notice Function for changing multiple token URIs
    /// @dev Can only be called by project owner
    /// @param _ids Token IDs that will have URI changed
    /// @param _URIs Token URIs to change to
    function setTokenURIs(uint256[] memory _ids, string[] memory _URIs)
        public
        onlyOwner
    {
        uint256 length = _ids.length;
        if (length != _URIs.length) {
            revert Mintpeg__InvalidLength();
        }
        for (uint256 i; i < length; i++) {
            _setTokenURI(_ids[i], _URIs[i]);
        }
    }

    /// @notice Update the address that the contract will make OperatorFilter checks against. When set to the zero
    /// address, checks will be bypassed. OnlyOwner
    /// @param _newRegistry The address of the new OperatorFilterRegistry
    function updateOperatorFilterRegistryAddress(
        IOperatorFilterRegistry _newRegistry
    ) external onlyOwner {
        _updateOperatorFilterRegistryAddress(_newRegistry);
    }

    /// @notice Function to burn a token
    /// @dev Can only be called by token owner
    /// @param _tokenId Token ID to be burnt
    function burn(uint256 _tokenId) external {
        if (ownerOf(_tokenId) != msg.sender) {
            revert Mintpeg__InvalidTokenOwner();
        }
        super._burn(_tokenId);
        _resetTokenRoyalty(_tokenId);
    }

    /// @notice Returns true if this contract implements the interface defined by `interfaceId`
    /// @dev Needs to be overridden cause two base contracts implement it
    /// @param _interfaceId InterfaceId to consider. Comes from type(InterfaceContract).interfaceId
    /// @return bool True if the considered interface is supported
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return
            ERC721Upgradeable.supportsInterface(_interfaceId) ||
            ERC2981Upgradeable.supportsInterface(_interfaceId) ||
            super.supportsInterface(_interfaceId);
    }

    /// @dev Update the address that the contract will make OperatorFilter checks against. When set to the zero
    /// address, checks will be bypassed.
    /// @param _newRegistry The address of the new OperatorFilterRegistry
    function _updateOperatorFilterRegistryAddress(
        IOperatorFilterRegistry _newRegistry
    ) private {
        operatorFilterRegistry = _newRegistry;
        emit OperatorFilterRegistryUpdated(_newRegistry);
    }

    /// @dev Checks if the address (the operator) trying to transfer the NFT is allowed
    /// @param operator Address of the operator
    function _checkFilterOperator(address operator) internal view virtual {
        IOperatorFilterRegistry registry = operatorFilterRegistry;
        // Check registry code length to facilitate testing in environments without a deployed registry.
        if (address(registry).code.length > 0) {
            if (!registry.isOperatorAllowed(address(this), operator)) {
                revert Mintpeg__OperatorNotAllowed(operator);
            }
        }
    }

    /// @dev `setApprovalForAll` wrapper to prevent the sender to approve a non-allowed operator
    /// @param operator Address being approved
    /// @param approved Whether the operator is approved or not
    function setApprovalForAll(address operator, bool approved)
        public
        override
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    /// @dev `aprove` wrapper to prevent the sender to approve a non-allowed operator
    /// @param operator Address being approved
    /// @param tokenId TokenID approved
    function approve(address operator, uint256 tokenId)
        public
        override
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    /// @dev `transferFrom` wrapper to prevent a non-allowed operator to transfer the NFT
    /// @param from Address to transfer from
    /// @param to Address to transfer to
    /// @param tokenId TokenID to transfer
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    /// @dev `safeTransferFrom` wrapper to prevent a non-allowed operator to transfer the NFT
    /// @param from Address to transfer from
    /// @param to Address to transfer to
    /// @param tokenId TokenID to transfer
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    /// @dev `safeTransferFrom` wrapper to prevent a non-allowed operator to transfer the NFT
    /// @param from Address to transfer from
    /// @param to Address to transfer to
    /// @param tokenId TokenID to transfer
    /// @param data Data to send along with a safe transfer check
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }
}

