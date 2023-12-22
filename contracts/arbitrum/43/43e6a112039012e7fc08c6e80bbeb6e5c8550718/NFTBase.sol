pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import "./Common.sol";
import "./IERC2981Upgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC1155Upgradeable.sol";
import "./ClonesUpgradeable.sol";
import "./StorageSlotUpgradeable.sol";

/**
 * @title Nevermined NFT Base
 * @author Nevermined
 *
 * It provides base functionality for all the Nevermined NFT implementations (ERC-1155 or ERC-721).
 * 
 * Nevermined NFT permissions are organized in different levels:
 *
 * 1. At the top level the NFT contracts are 'Ownable' so the owner (typically the deployer) of the contract
 *    can manage totally the NFT contract.
 * 2. At the second level we have the NFT contract operator role. The accounts having that role can do some
 *    operations like mint/burn/transfer. Typically this role is granted to some Nevermined contracts to 
 *    automate the execution of common functions, like the interaction with the service agreements.
 *    This role is managed using the  `grantOperatorRole` and `revokeOperatorRole` function
 * 3. At the bottom level the token/edition owners can provide some permissions to token/editions holders 
 *    via `setApprovalForAll`
 *   
 * @dev Implementation of the Royalties EIP-2981 base contract
 * See https://eips.ethereum.org/EIPS/eip-2981
 */
abstract contract NFTBase is IERC2981Upgradeable, CommonOwnable, AccessControlUpgradeable {

    // Role to operate the NFT contract
    bytes32 public constant NVM_OPERATOR_ROLE = keccak256('NVM_OPERATOR_ROLE');
    
    struct RoyaltyInfo {
        address receiver;
        uint256 royaltyAmount;
    }
    
    struct NFTAttributes {
        // Flag to control if NFTs config was already initialized
        bool nftInitialized;
        // The NFTs supply associated to the DID 
        uint256 nftSupply;
        // The max number of NFTs associated to the DID that can be minted 
        uint256 mintCap;
        // URL to NFT metadata        
        string nftURI;
    }
    
    // Mapping of Royalties per asset (DID)
    mapping(uint256 => RoyaltyInfo) internal _royalties;
    // Mapping of NFT Attributes object per tokenId
    mapping(uint256 => NFTAttributes) internal _nftAttributes;

    // @dev: Variable out of date. Kept because upgradeability
    // @dev: Use `_expirationBlock` mapping instead
    mapping(address => uint256) internal _expiration; // UNUSED 

    // Used as a URL where is stored the Metadata describing the NFT contract
    string private _contractMetadataUri;

    address public nvmConfig;
    
    event NFTCloned(
        address indexed _newAddress,
        address indexed _fromAddress,
        uint _ercType
    );

    modifier onlyOperatorOrOwner
    {
        require(
            owner() == _msgSender() || isOperator(_msgSender()),
            'Only operator or owner'
        );
        _;
    }

    /**
     * @dev getNvmConfigAddress get the address of the NeverminedConfig contract
     * @return NeverminedConfig contract address
     */
    function getNvmConfigAddress()
    public
    override
    view
    returns (address)
    {
        return nvmConfig;
    }

    function setNvmConfigAddress(address _addr)
    external
    onlyOwner
    {
        nvmConfig = _addr;
    }

    function _setNFTAttributes(
        uint256 tokenId,
        uint256 nftSupply,
        uint256 mintCap,
        string memory tokenURI
    )
    internal
    {
        _nftAttributes[tokenId].nftInitialized = true;
        _nftAttributes[tokenId].nftSupply = nftSupply;
        _nftAttributes[tokenId].mintCap = mintCap;
        _nftAttributes[tokenId].nftURI = tokenURI;
    }
    
    function _setNFTMetadata(
        uint256 tokenId,
        string memory tokenURI
    )
    internal
    {
        _nftAttributes[tokenId].nftInitialized = true;
        _nftAttributes[tokenId].nftURI = tokenURI;
    }

    function getNFTAttributes(
        uint256 tokenId
    )
    external
    view
    virtual
    returns (bool nftInitialized, uint256 nftSupply, uint256 mintCap, string memory nftURI)
    {
        NFTAttributes memory attributes = _nftAttributes[tokenId];
        nftInitialized = attributes.nftInitialized;
        nftSupply = attributes.nftSupply;
        mintCap = attributes.mintCap;
        nftURI = attributes.nftURI;
    }    
    
    function _setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint256 royaltyAmount
    )
    internal
    {
        require(royaltyAmount <= 1000000, 'ERC2981Royalties: Too high');
        _royalties[tokenId] = RoyaltyInfo(receiver, royaltyAmount);
    }    
    
    /**
     * @inheritdoc	IERC2981Upgradeable
     */
    function royaltyInfo(
        uint256 tokenId,
        uint256 value
    )
    external
    view
    override
    returns (address receiver, uint256 royaltyAmount)
    {
        RoyaltyInfo memory royalties = _royalties[tokenId];
        receiver = royalties.receiver;
        royaltyAmount = (value * royalties.royaltyAmount) / 100;
    }

    /**
    * @dev Record the URI storing the Metadata describing the NFT Contract
    *      More information about the file format here: 
    *      https://docs.opensea.io/docs/contract-level-metadata
    * @param _uri the URI (https, ipfs, etc) to the metadata describing the NFT Contract    
    */    
    function setContractMetadataUri(
        string memory _uri
    )
    public
    onlyOperatorOrOwner
    virtual
    {
        _contractMetadataUri = _uri;
    }
    
    function contractURI()
    public
    view
    returns (string memory) {
        return _contractMetadataUri;
    }

    function grantOperatorRole(
        address account
    )
    public
    virtual
    onlyOperatorOrOwner
    {
        AccessControlUpgradeable._setupRole(NVM_OPERATOR_ROLE, account);
    }

    function revokeOperatorRole(
        address account
    )
    public
    virtual
    onlyOperatorOrOwner
    {
        AccessControlUpgradeable._revokeRole(NVM_OPERATOR_ROLE, account);
    }

    function renounceOperatorRole()
    public
    virtual
    {
        AccessControlUpgradeable._revokeRole(NVM_OPERATOR_ROLE, _msgSender());
    }
    
    function isOperator(
        address operator
    )
    public
    view
    virtual
    returns (bool)
    {
        return AccessControlUpgradeable.hasRole(NVM_OPERATOR_ROLE, operator);
    }

    function _msgSender() internal override(CommonOwnable,ContextUpgradeable) virtual view returns (address ret) {
        return Common._msgSender();
    }
    function _msgData() internal override(CommonOwnable,ContextUpgradeable) virtual view returns (bytes calldata ret) {
        return Common._msgData();
    }

    function nftType() external pure virtual returns (bytes32) {
        return keccak256('');
    }
}

