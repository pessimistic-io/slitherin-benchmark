pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

abstract contract INVMConfig {

    bytes32 public constant GOVERNOR_ROLE = keccak256('NVM_GOVERNOR_ROLE');
    
    /**
    * @notice Event that is emitted when a parameter is changed
    * @param _whoChanged the address of the governor changing the parameter
    * @param _parameter the hash of the name of the parameter changed
    */
    event NeverminedConfigChange(
        address indexed _whoChanged,
        bytes32 indexed _parameter
    );

    /**
     * @notice The governor can update the Nevermined Marketplace fees
     * @param _marketplaceFee new marketplace fee 
     * @param _feeReceiver The address receiving the fee      
     */
    function setMarketplaceFees(
        uint256 _marketplaceFee,
        address _feeReceiver
    ) virtual external;

    /**
     * @notice Indicates if an address is a having the GOVERNOR role
     * @param _address The address to validate
     * @return true if is a governor 
     */    
    function isGovernor(
        address _address
    ) external view virtual returns (bool);

    /**
     * @notice Returns the marketplace fee
     * @return the marketplace fee
     */
    function getMarketplaceFee()
    external view virtual returns (uint256);

    /**
     * @notice Returns the receiver address of the marketplace fee
     * @return the receiver address
     */    
    function getFeeReceiver()
    external view virtual returns (address);

    /**
     * @notice Returns true if provenance should be stored in storage
     * @return true if provenance should be stored in storage
     */    
    function getProvenanceStorage()
    external view virtual returns (bool);

    /**
     * @notice Returns the address of OpenGSN forwarder contract
     * @return a address of OpenGSN forwarder contract
     */    
    function getTrustedForwarder()
    external virtual view returns(address);

    /**
     * @notice Indicates if an address is a having the OPERATOR role
     * @param _address The address to validate
     * @return true if is a governor 
     */    
    function hasNVMOperatorRole(address _address)
    external view virtual returns (bool);
}

