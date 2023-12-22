// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC1155Upgradeable.sol";
import "./NFTBase.sol";
import "./IExternalRegistry.sol";

/**
 *
 * @dev Implementation of the basic standard multi-token.
 * See https://eips.ethereum.org/EIPS/eip-1155
 */
contract NFT1155Upgradeable is ERC1155Upgradeable, NFTBase {
    
    // Token name
    string public name;

    // Token symbol
    string public symbol;

    IExternalRegistry internal nftRegistry;

    function initialize(
        address owner,
        address didRegistryAddress,
        string memory name_,
        string memory symbol_,
        string memory uri_
    )
    public
    virtual
    initializer  
    {
        require(
            owner != address(0) && didRegistryAddress != address(0),
            'Invalid address'
        );
        __NFT1155Upgradeable_init(owner, didRegistryAddress, name_, symbol_, uri_);
    }

    // solhint-disable-next-line
    function __NFT1155Upgradeable_init(
        address owner,
        address didRegistryAddress,
        string memory name_,
        string memory symbol_,
        string memory uri_
    )
    public
    virtual
    onlyInitializing
    {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC1155_init_unchained(uri_);
        __Ownable_init_unchained();
        
        AccessControlUpgradeable.__AccessControl_init();
    __NFT1155Upgradeable_unchained(owner, didRegistryAddress, name_, symbol_, uri_);
    }

    // solhint-disable-next-line
    function __NFT1155Upgradeable_unchained(
        address owner,
        address didRegistryAddress,
        string memory name_,
        string memory symbol_,
        string memory uri_
    )
    public
    virtual
    onlyInitializing
    {
        AccessControlUpgradeable._setupRole(NVM_OPERATOR_ROLE, _msgSender());
        AccessControlUpgradeable._setupRole(NVM_OPERATOR_ROLE, didRegistryAddress);
        AccessControlUpgradeable._setupRole(NVM_OPERATOR_ROLE, owner);
        setContractMetadataUri(uri_);
        name = name_;
        symbol = symbol_;

        nftRegistry = IExternalRegistry(didRegistryAddress);
        if (owner != _msgSender()) {
            transferOwnership(owner);
        }
    }

    function createClone(
        string memory _name,
        string memory _symbol,
        string memory _uri,
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
        NFT1155Upgradeable nftContract = NFT1155Upgradeable(cloneAddress);
        nftContract.initialize(_msgSender(), address(nftRegistry), _name, _symbol, _uri);
        for (uint256 i = 0; i < _operators.length; i++) {
            nftContract.grantOperatorRole(_operators[i]);
        }
        nftContract.renounceOperatorRole();
        emit NFTCloned(cloneAddress, implementation, 1155);
        return cloneAddress;
    }    
    
    /**
     * @dev See {IERC1155-isApprovedForAll}.
     */
    function isApprovedForAll(address account, address operator) public view virtual override returns (bool) {
        return super.isApprovedForAll(account, operator) || isOperator(operator);
    }

    function mint(uint256 id, uint256 amount) public {
        mint(_msgSender(), id, amount, '');
    }
    
    function mint(address to, uint256 id, uint256 amount, bytes memory data) public {
        // Only can mint if:
        require(isOperator(_msgSender()) || // is contract operator  
            to == owner() || // is contract owner
            _msgSender() == nftRegistry.getDIDOwner(bytes32(id)) // is asset owner
            , // Is operator or the NFT owner is _msgSender() 
            'only operator can mint');
        
        require(_nftAttributes[id].nftInitialized, 'NFT not initialized');
        if (_nftAttributes[id].mintCap > 0)    {
            require(_nftAttributes[id].nftSupply + amount <= _nftAttributes[id].mintCap, 'Cap exceeded');
        }
        
        // Update nftSupply
        _nftAttributes[id].nftSupply += amount;
        // Register provenance event
        nftRegistry.used(
            keccak256(abi.encode(id, _msgSender(), 'mint', amount, block.number)),
            bytes32(id), _msgSender(), keccak256('mint'), '', 'mint');
        
        _mint(to, id, amount, data);
    }

    function burn(uint256 id, uint256 amount) virtual public {
        burn(_msgSender(), id, amount); 
    }
    
    function burn(address to, uint256 id, uint256 amount) virtual public {
        require(balanceOf(to, id) >= amount, 'ERC1155: burn amount exceeds balance');
        require(
            isOperator(_msgSender()) || // Or the DIDRegistry is burning the NFT 
            to == _msgSender() || // Or the NFT owner is _msgSender() 
            isApprovedForAll(to, _msgSender()), // Or the _msgSender() is approved
            'ERC1155: caller is not owner nor approved'
        );

        // Update nftSupply
        _nftAttributes[id].nftSupply -= amount;
        // Register provenance event
        nftRegistry.used(
            keccak256(abi.encode(id, _msgSender(), 'burn', amount, block.number)),
                bytes32(id), _msgSender(), keccak256('burn'), '', 'burn');
        
        _burn(to, id, amount);
    }
    
    function uri(uint256 tokenId) public view override returns (string memory) {
        return _nftAttributes[tokenId].nftURI;
    }

    /**
    * @dev Record some NFT Metadata
    * @param tokenId the id of the asset with the royalties associated
    * @param nftSupply the NFTs supply
    * @param mintCap the max number of editions that can be minted
    * @param nftURI the URI (https, ipfs, etc) to the metadata describing the NFT
    */
    function setNFTAttributes(
        uint256 tokenId,
        uint256 nftSupply,
        uint256 mintCap,    
        string memory nftURI
    )
    public
    {
        require(isOperator(_msgSender()), 'only nft operator');
        _setNFTAttributes(tokenId, nftSupply, mintCap, nftURI);
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
    override(ERC1155Upgradeable, AccessControlUpgradeable, IERC165Upgradeable) 
    returns (bool) 
    {
        return AccessControlUpgradeable.supportsInterface(interfaceId)
        || ERC1155Upgradeable.supportsInterface(interfaceId)
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
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
    internal
    virtual
    override
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        require(
            from == address(0) || // We exclude mints
            to == address(0) || // We exclude burns
            isOperator(_msgSender()) // Only NFT Contract Operators (Nevermined condition contracts)
            , 'only proxy'
        );
    }

    function nftType() external pure override virtual returns (bytes32) {
        return keccak256('nft1155');
    }
    
}

