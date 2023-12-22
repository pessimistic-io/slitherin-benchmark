pragma solidity ^0.8.0;

import "./NFT721Upgradeable.sol";
import "./ERC165StorageUpgradeable.sol";
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

contract NFT721SubscriptionUpgradeable is NFT721Upgradeable {
    
    struct MintedTokens {
        uint256 tokenId;
        uint256 expirationBlock;
        uint256 mintBlock;
    }

    mapping(address => MintedTokens[]) internal _tokens;

    // It represents the NFT type. It is used to identify the NFT type in the Nevermined ecosystem
    // solhint-disable-next-line
    bytes32 public constant override nftType = keccak256('nft721-subscription');

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
    override
    initializer
    {
        __NFT721Upgradeable_init(owner, didRegistryAddress, name, symbol, uri, cap);
    }
    
    /**
     * @dev This mint function allows to define when the NFT expires. 
     * The minter should calculate this block number depending on the network velocity
     * 
     * @dev TransferNFT721Condition needs to have the `NVM_OPERATOR_ROLE`
     */
    function mint(address to, uint256 tokenId, uint256 expirationBlock) public {
        super.mint(to, tokenId);
        _nftAttributes[tokenId].nftSupply += 1;
        _tokens[to].push( MintedTokens(tokenId, expirationBlock, block.number));
    }

    function burn(
        uint256 tokenId
    )
    override
    public
    {
        require(
            isOperator(_msgSender()) || // Or the DIDRegistry is burning the NFT 
            super.ownerOf(tokenId) == _msgSender(), // Or the _msgSender() is owner and have balance
            'ERC721: caller is not owner or not have balance'
        );
        // Update nftSupply
        _nftAttributes[tokenId].nftSupply -= 1;
        // Register provenance event
        nftRegistry.used(
            keccak256(abi.encode(tokenId, _msgSender(), 'burn', 1, block.number)),
            bytes32(tokenId), _msgSender(), keccak256('burn'), '', 'burn');

        _burn(tokenId);
        
        for (uint index = 0; index < _tokens[_msgSender()].length; index++) {
            if (_tokens[_msgSender()][index].tokenId == tokenId) {
                delete _tokens[_msgSender()][index];
                break;
            }
        }
    }    
    
    /**
     * @dev See {IERC721-balanceOf}.
     */    
    function balanceOf(address owner) public view override returns (uint256) {
        uint256 _balance;
        for (uint index = 0; index < _tokens[owner].length; index++) {
            if (_tokens[owner][index].mintBlock > 0 && 
                (_tokens[owner][index].expirationBlock == 0 || _tokens[owner][index].expirationBlock > block.number))
                _balance += 1;
        }
        
        return _balance;
    }

    function whenWasMinted(address owner) public view returns (uint256[] memory) {
        uint256[] memory _whenMinted = new uint256[](_tokens[owner].length);
        for (uint index = 0; index < _tokens[owner].length; index++) {
            _whenMinted[index] = _tokens[owner][index].mintBlock;
        }
        return _whenMinted;
    }

    function getMintedEntries(address owner) public view returns (MintedTokens[] memory) {
        return _tokens[owner];
    }    
}

