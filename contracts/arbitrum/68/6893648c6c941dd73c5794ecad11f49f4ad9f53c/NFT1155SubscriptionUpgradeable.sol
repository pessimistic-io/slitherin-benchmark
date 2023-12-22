pragma solidity ^0.8.0;

import "./ERC165StorageUpgradeable.sol";
import "./NFT1155Upgradeable.sol";
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

contract NFT1155SubscriptionUpgradeable is NFT1155Upgradeable {
    
    struct MintedTokens {
        uint256 amountMinted;
        uint256 expirationBlock;
        uint256 mintBlock;
        bool isMintOps; // true means mint, false means burn
    }

    mapping(bytes32 => MintedTokens[]) internal _tokens;

    // It represents the NFT type. It is used to identify the NFT type in the Nevermined ecosystem
    // solhint-disable-next-line
    bytes32 public constant override nftType = keccak256('nft1155-subscription');
    
    function initialize(
        address owner,
        address didRegistryAddress,
        string memory name_,
        string memory symbol_,
        string memory uri_,
        address nvmConfig_
    )
    public
    override
    virtual
    initializer
    {
        __NFT1155Upgradeable_init(owner, didRegistryAddress, name_, symbol_, uri_, nvmConfig_);
    }
    
    
    function mint(address to, uint256 tokenId, uint256 amount, bytes memory data) virtual override public {
        mint(to, tokenId, amount, 0, data);
    }    
    
    /**
     * @dev This mint function allows to define when the tokenId of the NFT expires. 
     * The minter should calculate this block number depending on the network velocity
     * 
     */
    function mint(address to, uint256 tokenId, uint256 amount, uint256 expirationBlock, bytes memory data) public virtual {
        super.mint(to, tokenId, amount, data);
        bytes32 _key = _getTokenKey(to, tokenId);

        _tokens[_key].push( MintedTokens(amount, expirationBlock, block.number, true));
    }

    function burn(uint256 id, uint256 amount) override public {
        burn(_msgSender(), id, amount);
    }    
    
    function burn(address to, uint256 id, uint256 amount) override public {
        require(balanceOf(to, id) >= amount, 'ERC1155: burn amount exceeds balance');
        require(
            isOperator(_msgSender()) || // Or the DIDRegistry is burning the NFT 
            to == _msgSender() || // Or the NFT owner is _msgSender() 
            nftRegistry.isDIDProvider(bytes32(id), _msgSender()) || // Or the DID Provider (Node) is burning the NFT
            isApprovedForAll(to, _msgSender()), // Or the _msgSender() is approved
            'ERC1155: caller is not owner nor approved'
        );

        // Update nftSupply
        _nftAttributes[id].nftSupply -= amount;
        // Register provenance event
        nftRegistry.used(
            keccak256(abi.encode(id, _msgSender(), 'burn', amount, block.number)),
            bytes32(id), _msgSender(), keccak256('burn'), '', 'burn');
        
        bytes32 _key = _getTokenKey(to, id);

        uint256 _pendingToBurn = amount;

        for (uint index = 0; index < _tokens[_key].length; index++) {
            if (_tokens[_key][index].expirationBlock == 0 || _tokens[_key][index].expirationBlock > block.number)   {
                if (_pendingToBurn <= _tokens[_key][index].amountMinted) {
                    _tokens[_key].push( MintedTokens(_pendingToBurn, _tokens[_key][index].expirationBlock, block.number, false));
                    break;
                } else {
                    _pendingToBurn -= _tokens[_key][index].amountMinted;
                    _tokens[_key].push( MintedTokens(_tokens[_key][index].amountMinted, _tokens[_key][index].expirationBlock, block.number, false));
                }   
            }
        }
    }    
    
    /**
     * @dev See {NFT1155Upgradeableable-balanceOf}.
     */
    function balanceOf(address account, uint256 tokenId) public view virtual override returns (uint256) {

        bytes32 _key = _getTokenKey(account, tokenId);
        uint256 _amountBurned;
        uint256 _amountMinted;
        for (uint index = 0; index < _tokens[_key].length; index++) {
            if (_tokens[_key][index].mintBlock > 0 &&
                (_tokens[_key][index].expirationBlock == 0 || _tokens[_key][index].expirationBlock > block.number)) {
                if (_tokens[_key][index].isMintOps)
                    _amountMinted += _tokens[_key][index].amountMinted;
                else
                    _amountBurned += _tokens[_key][index].amountMinted;
            }
        }

        if (_amountBurned >= _amountMinted)
            return 0;
        else
            return _amountMinted - _amountBurned;
    }
    
    function whenWasMinted(address owner, uint256 tokenId) public view returns (uint256[] memory) {
        bytes32 _key = _getTokenKey(owner, tokenId);
        uint256[] memory _whenMinted = new uint256[](_tokens[_key].length);
        for (uint index = 0; index < _tokens[_key].length; index++) {
            _whenMinted[index] = _tokens[_key][index].mintBlock;
        }
        return _whenMinted;
    }
    
    function getMintedEntries(address owner, uint256 tokenId) public view returns (MintedTokens[] memory) {
        return _tokens[_getTokenKey(owner, tokenId)];
    }
    
    function _getTokenKey(address account, uint256 tokenId) internal pure returns (bytes32) {
        return keccak256(abi.encode(account, tokenId));
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        uint256[] memory expirations,
        bytes memory data
    ) external {
        require(ids.length == amounts.length && ids.length == expirations.length, 'mintBatch: lengths do not match');
        for (uint i = 0; i < ids.length; i++) {
            mint(to, ids[i], amounts[i], expirations[i], data);
        }
    }

    function burnBatch(
        address from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external {
        require(ids.length == amounts.length, 'burnBatch: lengths do not match');
        for (uint i = 0; i < ids.length; i++) {
            burn(from, ids[i], amounts[i]);
        }
    }
}

