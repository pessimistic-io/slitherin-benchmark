pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import "./IRoyaltyScheme.sol";

/**
 * @title DID Registry Library
 * @author Nevermined
 *
 * @dev All function calls are currently implemented without side effects
 */
library DIDRegistryLibrary {

    // DIDRegistry Entity
    struct DIDRegister {
        // DIDRegistry entry owner
        address owner;
        // The percent of the sale that is going back to the original `creator` in the secondary market  
        uint8 royalties;
        // Flag to control if NFTs config was already initialized
        bool nftInitialized;
        // Address of the NFT Contract
        address nftContractAddress;
        // DIDRegistry original creator, this can't be modified after the asset is registered 
        address creator;
        // Checksum associated to the DID
        bytes32 lastChecksum;
        // URL to the metadata associated to the DID
        string  url;
        // Who was the last one updated the entry
        address lastUpdatedBy;
        // When was the last time was updated
        uint256 blockNumberUpdated;
        // Providers able to manage this entry
        address[] providers;
        // Delegates able to register provenance events on behalf of the owner or providers
        address[] delegates;
        // The NFTs supply associated to the DID 
//        uint256 nftSupply;
        // The max number of NFTs associated to the DID that can be minted 
//        uint256 mintCap;
        address royaltyRecipient;
        IRoyaltyScheme royaltyScheme;
        // URL to the Metadata in Immutable storage 
        string  immutableUrl;        
    }

    // List of DID's registered in the system
    struct DIDRegisterList {
        mapping(bytes32 => DIDRegister) didRegisters;
    }

    /**
     * @notice update the DID store
     * @dev access modifiers and storage pointer should be implemented in DIDRegistry
     * @param _self refers to storage pointer
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _checksum includes a one-way HASH calculated using the DDO content
     * @param _url includes the url resolving to the DID Document (DDO)
     * @param _sender the address of the user updating the entry
     * @param _immutableUrl includes the url to the DDO in immutable storage     
     */
    function update(
        DIDRegisterList storage _self,
        bytes32 _did,
        bytes32 _checksum,
        string memory _url,
        address _sender,
        string memory _immutableUrl
    )
    internal
    {
        address didOwner = _self.didRegisters[_did].owner;
        address creator = _self.didRegisters[_did].creator;
        
        if (didOwner == address(0)) {
            didOwner = _sender;
            creator = didOwner;
        }

        _self.didRegisters[_did].owner = didOwner;
        _self.didRegisters[_did].creator = creator;
        _self.didRegisters[_did].lastChecksum = _checksum;
        _self.didRegisters[_did].url = _url;
        _self.didRegisters[_did].lastUpdatedBy = _sender;
        _self.didRegisters[_did].owner = didOwner;
        _self.didRegisters[_did].blockNumberUpdated = block.number;
        _self.didRegisters[_did].immutableUrl = _immutableUrl;
    }

    /**
     * @notice initializeNftConfig creates the initial setup of NFTs minting and royalties distribution.
     * After this initial setup, this data can't be changed anymore for the DID given, even for the owner of the DID.
     * The reason of this is to avoid minting additional NFTs after the initial agreement, what could affect the 
     * valuation of NFTs of a DID already created. 
     * @dev update the DID registry providers list by adding the nftContract and royalties configuration
     * @param _self refers to storage pointer
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _royaltyHandler contract for handling royalties
     */
    function initializeNftConfig(
        DIDRegisterList storage _self,
        bytes32 _did,
        address _nftContractAddress,
        IRoyaltyScheme _royaltyHandler
    )
    internal
    {
        require(_self.didRegisters[_did].owner != address(0), 'DID not stored');
        require(!_self.didRegisters[_did].nftInitialized, 'NFT already initialized');
        
        _self.didRegisters[_did].nftContractAddress = _nftContractAddress;
        _self.didRegisters[_did].royaltyScheme = _royaltyHandler;
        _self.didRegisters[_did].nftInitialized = true;
    }

    function initializeNft721Config(
        DIDRegisterList storage _self,
        bytes32 _did,
        address _nftContractAddress,
        IRoyaltyScheme _royaltyHandler
    )
    internal
    {
        require(_self.didRegisters[_did].owner != address(0), 'DID not stored');
        require(!_self.didRegisters[_did].nftInitialized, 'NFT already initialized');
        
        _self.didRegisters[_did].nftContractAddress = _nftContractAddress;
        _self.didRegisters[_did].royaltyScheme = _royaltyHandler;
        _self.didRegisters[_did].nftInitialized = true;
    }


    /**
     * @notice areRoyaltiesValid checks if for a given DID and rewards distribution, this allocate the  
     * original creator royalties properly
     * @param _self refers to storage pointer
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _amounts refers to the amounts to reward
     * @param _receivers refers to the receivers of rewards
     * @return true if the rewards distribution respect the original creator royalties
     */
    function areRoyaltiesValid(
        DIDRegisterList storage _self,
        bytes32 _did,
        uint256[] memory _amounts,
        address[] memory _receivers,
        address _tokenAddress
    )
    internal
    view
    returns (bool)
    {
        if (address(_self.didRegisters[_did].royaltyScheme) != address(0)) {
            return _self.didRegisters[_did].royaltyScheme.check(_did, _amounts, _receivers, _tokenAddress);
        }
        // If there are no royalties everything is good
        if (_self.didRegisters[_did].royalties == 0) {
            return true;
        }

        // If (sum(_amounts) == 0) - It means there is no payment so everything is valid
        // returns true;
        uint256 _totalAmount = 0;
        for(uint i = 0; i < _amounts.length; i++)
            _totalAmount = _totalAmount + _amounts[i];
        if (_totalAmount == 0)
            return true;
        
        // If (_did.creator is not in _receivers) - It means the original creator is not included as part of the payment
        // return false;
        address recipient = _self.didRegisters[_did].creator;
        if (_self.didRegisters[_did].royaltyRecipient != address(0)) {
            recipient = _self.didRegisters[_did].royaltyRecipient;
        }
        bool found = false;
        uint256 index;
        for (index = 0; index < _receivers.length; index++) {
            if (recipient == _receivers[index])  {
                found = true;
                break;
            }
        }

        // The creator royalties are not part of the rewards
        if (!found) {
            return false;
        }

        // If the amount to receive by the creator is lower than royalties the calculation is not valid
        // return false;
        uint256 _requiredRoyalties = _totalAmount * _self.didRegisters[_did].royalties / 100;

        // Check if royalties are enough
        // Are we paying enough royalties in the secondary market to the original creator?
        return (_amounts[index] >= _requiredRoyalties);
    }


    /**
     * @notice addProvider add provider to DID registry
     * @dev update the DID registry providers list by adding a new provider
     * @param _self refers to storage pointer
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param provider the provider's address 
     */
    function addProvider(
        DIDRegisterList storage _self,
        bytes32 _did,
        address provider
    )
    internal
    {
        require(
            provider != address(0) && provider != address(this),
            'Invalid provider'
        );
        
        if (!isProvider(_self, _did, provider)) {
            _self.didRegisters[_did].providers.push(provider);
        }

    }

    /**
     * @notice removeProvider remove provider from DID registry
     * @dev update the DID registry providers list by removing an existing provider
     * @param _self refers to storage pointer
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _provider the provider's address 
     */
    function removeProvider(
        DIDRegisterList storage _self,
        bytes32 _did,
        address _provider
    )
    internal
    returns(bool)
    {
        require(
            _provider != address(0),
            'Invalid provider'
        );

        int256 i = getProviderIndex(_self, _did, _provider);

        if (i == -1) {
            return false;
        }

        delete _self.didRegisters[_did].providers[uint256(i)];

        return true;
    }

    /**
     * @notice updateDIDOwner transfer DID ownership to a new owner
     * @param _self refers to storage pointer
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _newOwner the new DID owner address
     */
    function updateDIDOwner(
        DIDRegisterList storage _self,
        bytes32 _did,
        address _newOwner
    )
    internal
    {
        require(_newOwner != address(0));
        _self.didRegisters[_did].owner = _newOwner;
    }

    /**
     * @notice isProvider check whether DID provider exists
     * @param _self refers to storage pointer
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _provider the provider's address 
     * @return true if the provider already exists
     */
    function isProvider(
        DIDRegisterList storage _self,
        bytes32 _did,
        address _provider
    )
    internal
    view
    returns(bool)
    {
        if (getProviderIndex(_self, _did, _provider) == -1)
            return false;
        return true;
    }


    
    /**
     * @notice getProviderIndex get the index of a provider
     * @param _self refers to storage pointer
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param provider the provider's address 
     * @return the index if the provider exists otherwise return -1
     */
    function getProviderIndex(
        DIDRegisterList storage _self,
        bytes32 _did,
        address provider
    )
    private
    view
    returns(int256 )
    {
        for (uint256 i = 0;
            i < _self.didRegisters[_did].providers.length; i++) {
            if (provider == _self.didRegisters[_did].providers[i]) {
                return int(i);
            }
        }

        return - 1;
    }

    //////////// DELEGATE METHODS

    /**
     * @notice addDelegate add delegate to DID registry
     * @dev update the DID registry delegates list by adding a new delegate
     * @param _self refers to storage pointer
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param delegate the delegate's address 
     */
    function addDelegate(
        DIDRegisterList storage _self,
        bytes32 _did,
        address delegate
    )
    internal
    {
        require(delegate != address(0) && delegate != address(this));

        if (!isDelegate(_self, _did, delegate)) {
            _self.didRegisters[_did].delegates.push(delegate);
        }

    }

    /**
     * @notice removeDelegate remove delegate from DID registry
     * @dev update the DID registry delegates list by removing an existing delegate
     * @param _self refers to storage pointer
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _delegate the delegate's address 
     */
    function removeDelegate(
        DIDRegisterList storage _self,
        bytes32 _did,
        address _delegate
    )
    internal
    returns(bool)
    {
        require(_delegate != address(0));

        int256 i = getDelegateIndex(_self, _did, _delegate);

        if (i == -1) {
            return false;
        }

        delete _self.didRegisters[_did].delegates[uint256(i)];

        return true;
    }

    /**
     * @notice isDelegate check whether DID delegate exists
     * @param _self refers to storage pointer
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _delegate the delegate's address 
     * @return true if the delegate already exists
     */
    function isDelegate(
        DIDRegisterList storage _self,
        bytes32 _did,
        address _delegate
    )
    internal
    view
    returns(bool)
    {
        if (getDelegateIndex(_self, _did, _delegate) == -1)
            return false;
        return true;
    }

    /**
     * @notice getDelegateIndex get the index of a delegate
     * @param _self refers to storage pointer
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param delegate the delegate's address 
     * @return the index if the delegate exists otherwise return -1
     */
    function getDelegateIndex(
        DIDRegisterList storage _self,
        bytes32 _did,
        address delegate
    )
    private
    view
    returns(int256)
    {
        for (uint256 i = 0;
            i < _self.didRegisters[_did].delegates.length; i++) {
            if (delegate == _self.didRegisters[_did].delegates[i]) {
                return int(i);
            }
        }

        return - 1;
    }

}

