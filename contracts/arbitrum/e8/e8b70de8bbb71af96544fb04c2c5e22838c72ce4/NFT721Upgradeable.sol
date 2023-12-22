pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import "./NFTBase.sol";
import "./ERC721Upgradeable.sol";
import "./CountersUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./IExternalRegistry.sol";


/**
 *
 * @dev Implementation of the basic standard multi-token.
 */
contract NFT721Upgradeable is ERC721Upgradeable, NFTBase {
    
    uint256 private _nftContractCap;

    IExternalRegistry internal nftRegistry;
    
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using StringsUpgradeable for uint256;

    CountersUpgradeable.Counter private _counterMinted;
    
    // solhint-disable-next-line
    function initialize(
        address owner,
        address didRegistryAddress,
        string memory name,
        string memory symbol,
        string memory uri,
        uint256 cap
    )
    public
    virtual
    initializer
    {
        __NFT721Upgradeable_init(owner, didRegistryAddress, name, symbol, uri, cap);
    }

    // solhint-disable-next-line
    function __NFT721Upgradeable_init(
        address owner,
        address didRegistryAddress,
        string memory name,
        string memory symbol,
        string memory uri,
        uint256 cap
    )
    internal
    onlyInitializing
    {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC721_init_unchained(name, symbol);
        __Ownable_init_unchained();
        AccessControlUpgradeable.__AccessControl_init();
        __NFT721Upgradeable_unchained(owner, didRegistryAddress, uri, cap);
    }

    // solhint-disable-next-line
    function __NFT721Upgradeable_unchained(
        address owner,
        address didRegistryAddress,
        string memory uri,
        uint256 cap
    )
    internal
    onlyInitializing
    {
        AccessControlUpgradeable._setupRole(NVM_OPERATOR_ROLE, _msgSender());
        AccessControlUpgradeable._setupRole(NVM_OPERATOR_ROLE, didRegistryAddress);
        AccessControlUpgradeable._setupRole(NVM_OPERATOR_ROLE, owner);
        setContractMetadataUri(uri);
        _nftContractCap = cap;

        nftRegistry = IExternalRegistry(didRegistryAddress);
        if (owner != _msgSender()) {
            transferOwnership(owner);
        }
    }

    function createClone(
        string memory name,
        string memory symbol,
        string memory uri,
        uint256 cap,
        address[] memory _operators
    )
    external
    virtual
    returns (address)
    {
        address implementation = StorageSlotUpgradeable.getAddressSlot(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc).value;
        if (implementation == address(0)) {
            implementation = address(this);
        }        
        address cloneAddress = ClonesUpgradeable.clone(implementation);
        NFT721Upgradeable nftContract = NFT721Upgradeable(cloneAddress);
        nftContract.initialize(_msgSender(), address(nftRegistry), name, symbol, uri, cap);
        for (uint256 i = 0; i < _operators.length; i++) {
            nftContract.grantOperatorRole(_operators[i]);
        }
        nftContract.renounceOperatorRole();
        emit NFTCloned(cloneAddress, implementation, 721);
        return cloneAddress;
    }
    
    function isApprovedForAll(
        address account, 
        address operator
    ) 
    public 
    view 
    virtual 
    override
    returns (bool) 
    {
        return super.isApprovedForAll(account, operator) || isOperator(operator);
    }
    
    function mint(
        address to,
        uint256 tokenId
    )
    public
    virtual
    {
        require(isOperator(_msgSender()) || to == owner(), 'only nft operator can mint');
        require(_nftContractCap == 0 || _counterMinted.current() < _nftContractCap,
            'ERC721: Cap exceed'
        );
        
        // Update nftSupply
        _counterMinted.increment();
        _nftAttributes[tokenId].nftSupply = _counterMinted.current();
        _nftAttributes[tokenId].nftURI = '';
        
        // Register provenance event
        nftRegistry.used(
            keccak256(abi.encode(tokenId, _msgSender(), 'mint', 1, block.number)),
            bytes32(tokenId), _msgSender(), keccak256('mint'), '', 'mint');
        
        _mint(to, tokenId);
    }

    function mint(
        uint256 tokenId
    )
    public
    virtual
    {
        return mint(_msgSender(), tokenId);
    }    
    
    function getHowManyMinted()
    public
    view
    returns (uint256)
    {
        return _counterMinted.current();
    }
    
    /**
    * @dev Burning tokens does not decrement the counter of tokens minted!
    *      This is by design.
    */
    function burn(
        uint256 tokenId
    ) 
    virtual
    public 
    {
        require(
            isOperator(_msgSender()) || // Or the DIDRegistry is burning the NFT 
            balanceOf(_msgSender()) > 0, // Or the _msgSender() is owner and have balance
            'ERC721: caller is not owner or not have balance'
        );
        // Update nftSupply
        _nftAttributes[tokenId].nftSupply -= 1;
        // Register provenance event
        nftRegistry.used(
            keccak256(abi.encode(tokenId, _msgSender(), 'burn', 1, block.number)),
                bytes32(tokenId), _msgSender(), keccak256('burn'), '', 'burn');
        
        _burn(tokenId);
    }

    function _baseURI() 
    internal 
    view 
    override
    virtual
    returns (string memory) 
    {
        return contractURI();
    }
    
    /**
    * @dev Record some NFT Metadata
    * @param tokenId the id of the asset with the royalties associated
    * @param nftURI the URI (https, ipfs, etc) to the metadata describing the NFT
    */
    function setNFTMetadata(
        uint256 tokenId,
        string memory nftURI
    )
    public
    {
        require(isOperator(_msgSender()), 'only nft operator');
        _setNFTMetadata(tokenId, nftURI);
    }

    function tokenURI(
        uint256 tokenId
    ) 
    public 
    view 
    virtual 
    override (ERC721Upgradeable)
    returns (string memory) 
    {
        string memory baseURI = _baseURI();
        if (_exists(tokenId))
            return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toHexString())) : '';
        else
            return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI)) : '';        
    }    
    
    /**
    * @dev Record the asset royalties
    * @param tokenId the id of the asset with the royalties associated
    * @param receiver the receiver of the royalties (the original creator)
    * @param royaltyAmount percentage (no decimals, between 0 and 100)    
    */
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint256 royaltyAmount
    )
    public
    {
        require(isOperator(_msgSender()), 'only nft operator');
        _setTokenRoyalty(tokenId, receiver, royaltyAmount);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) 
    public 
    view 
    virtual 
    override(ERC721Upgradeable, AccessControlUpgradeable, IERC165Upgradeable) 
    returns (bool) 
    {
        return AccessControlUpgradeable.supportsInterface(interfaceId)
        || ERC721Upgradeable.supportsInterface(interfaceId)
        || interfaceId == type(IERC2981Upgradeable).interfaceId;
    }
    
    function _msgSender() internal override(NFTBase,ContextUpgradeable) virtual view returns (address ret) {
        return Common._msgSender();
    }
    function _msgData() internal override(NFTBase,ContextUpgradeable) virtual view returns (bytes calldata ret) {
        return Common._msgData();
    }
    
    /**
    * @dev It protects NFT transfers to force going through service agreements and enforce royalties
    */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256, /* firstTokenId */
        uint256 batchSize
    ) 
    internal 
    virtual 
    override 
    {
        require(
            from == address(0) || // We exclude mints
            to == address(0) || // We exclude burns
            isOperator(_msgSender()) // Only NFT Contract Operators (Nevermined condition contracts)
        , 'only proxy'
        );
        super._beforeTokenTransfer(from, to, 0, batchSize);
    }

    function nftType() external pure override virtual returns (bytes32) {
        return keccak256('nft721');
    }
}

