pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import "./Condition.sol";


interface ILockPayment {

    event Fulfilled(
        bytes32 indexed _agreementId,
        bytes32 indexed _did,
        bytes32 indexed _conditionId,
        address _rewardAddress,
        address _tokenAddress,
        address[] _receivers,
        uint256[] _amounts
    );

    /**
     * @notice hashValues generates the hash of condition inputs 
     *        with the following parameters
     * @param _did the asset decentralized identifier 
     * @param _rewardAddress the contract address where the reward is locked       
     * @param _tokenAddress the ERC20 contract address to use during the lock payment. 
     *        If the address is 0x0 means we won't use a ERC20 but ETH for payment     
     * @param _amounts token amounts to be locked/released
     * @param _receivers receiver's addresses
     * @return bytes32 hash of all these values 
     */
    function hashValues(
        bytes32 _did,
        address _rewardAddress,
        address _tokenAddress,
        uint256[] memory _amounts,
        address[] memory _receivers
    )
    external
    pure
    returns (bytes32);

    /**
     * @notice fulfill requires valid token transfer in order 
     *           to lock the amount of tokens based on the SEA
     * @param _agreementId the agreement identifier
     * @param _did the asset decentralized identifier
     * @param _rewardAddress the contract address where the reward is locked
     * @param _tokenAddress the ERC20 contract address to use during the lock payment. 
     * @param _amounts token amounts to be locked/released
     * @param _receivers receiver's addresses
     * @return condition state
     */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address payable _rewardAddress,
        address _tokenAddress,
        uint256[] memory _amounts,
        address[] memory _receivers
    )
    external
    payable
    returns (ConditionStoreLibrary.ConditionState);    
    

}

