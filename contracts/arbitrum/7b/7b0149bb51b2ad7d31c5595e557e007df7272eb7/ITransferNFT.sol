pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import "./Condition.sol";
import "./DIDRegistry.sol";
import "./ReentrancyGuardUpgradeable.sol";

interface ITransferNFT {

    event Fulfilled(
        bytes32 indexed _agreementId,
        bytes32 indexed _did,
        address indexed _receiver,
        uint256 _amount,
        bytes32 _conditionId,
        address _contract
    );
    

   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _did refers to the DID in which secret store will issue the decryption keys
    * @param _nftReceiver is the address of the granted user or the DID provider
    * @param _nftAmount amount of NFTs to transfer   
    * @param _lockCondition lock condition identifier   
    * @param _transfer Indicates if the NFT will be transferred (true) or minted (false)     
    * @return bytes32 hash of all these values 
    */
    function hashValues(
        bytes32 _did,
        address _nftHolder,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockCondition,
        address _contract,
        bool _transfer
    )
        external
        pure
        returns (bytes32);

    /**
     * @notice fulfill the transfer NFT condition
     * @dev Fulfill method transfer a certain amount of NFTs 
     *       to the _nftReceiver address. 
     *       When true then fulfill the condition
     * @param _agreementId agreement identifier
     * @param _did refers to the DID in which secret store will issue the decryption keys
     * @param _nftReceiver is the address of the account to receive the NFT
     * @param _nftAmount amount of NFTs to transfer  
     * @param _lockPaymentCondition lock payment condition identifier
     * @param _transfer Indicates if the NFT will be transferred (true) or minted (false)     
     * @return condition state (Fulfilled/Aborted)
     */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockPaymentCondition,
        address _contract,        
        bool _transfer
    )
    external
    returns (ConditionStoreLibrary.ConditionState);

    /**
     * @notice returns if the default NFT contract address
     * @dev The default NFT contract address was given to the Transfer Condition during
     * the contract initialization
     * 
     * @return the NFT contract address used by default in the transfer condition 
     */
    function getNFTDefaultAddress()
    external
    view
    returns (address);
    
}


