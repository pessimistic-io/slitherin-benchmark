pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./INVMConfig.sol";

contract NeverminedConfig is 
    OwnableUpgradeable,
    AccessControlUpgradeable,
INVMConfig
{

    ///////////////////////////////////////////////////////////////////////////////////////
    /////// NEVERMINED GOVERNABLE VARIABLES ////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////
    
    // @notice The fee charged by Nevermined for using the Service Agreements.
    // Integer representing a 2 decimal number. i.e 350 means a 3.5% fee
    uint256 public marketplaceFee;

    // @notice The address that will receive the fee charged by Nevermined per transaction
    // See `marketplaceFee`
    address public feeReceiver;

    // @notice Switch to turn off provenance in storage. By default the storage is on
    bool public provenanceOff;

    address public trustedForwarder;

    ///////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////
    
    
    /**
     * @notice Used to initialize the contract during delegator constructor
     * @param _owner The owner of the contract
     * @param _governor The address to be granted with the `GOVERNOR_ROLE`
     */
    function initialize(
        address _owner,
        address _governor,
        bool _provenanceOff
    )
    public
    initializer
    {
        __Ownable_init();
        transferOwnership(_owner);

        AccessControlUpgradeable.__AccessControl_init();
        AccessControlUpgradeable._setupRole(DEFAULT_ADMIN_ROLE, _owner);
        AccessControlUpgradeable._setupRole(GOVERNOR_ROLE, _governor);
        provenanceOff = _provenanceOff;
    }

    function setMarketplaceFees(
        uint256 _marketplaceFee,
        address _feeReceiver
    )
    external
    virtual
    override
    onlyGovernor(msg.sender)
    {
        require(
            _marketplaceFee >=0 && _marketplaceFee <= 1000000,
            'NeverminedConfig: Fee must be between 0 and 100 percent'
        );
        
        if (_marketplaceFee > 0)    {
            require(
                _feeReceiver != address(0),
                'NeverminedConfig: Receiver can not be 0x0'
            );            
        }

        marketplaceFee = _marketplaceFee;
        feeReceiver = _feeReceiver;
        emit NeverminedConfigChange(msg.sender, keccak256('marketplaceFee'));
        emit NeverminedConfigChange(msg.sender, keccak256('feeReceiver'));
    }

    function setGovernor(address _address) external onlyOwner {
        _grantRole(GOVERNOR_ROLE, _address);
    }

    function isGovernor(
        address _address
    )
    external
    view
    override
    returns (bool)
    {
        return hasRole(GOVERNOR_ROLE, _address);
    }

    function getMarketplaceFee()
    external
    view
    override 
    returns (uint256) 
    {
        return marketplaceFee;
    }

    function getFeeReceiver()
    external
    view
    override 
    returns (address)
    {
        return feeReceiver;
    }
    
    function getProvenanceStorage()
    external
    view
    override 
    returns (bool)
    {
        return !provenanceOff;
    }

    function getTrustedForwarder()
    external override virtual view returns(address) {
        return trustedForwarder;
    }

    function setTrustedForwarder(address forwarder)
    external onlyGovernor(msg.sender) {
        trustedForwarder = forwarder;
    }

    modifier onlyGovernor(address _address)
    {
        require(
            hasRole(GOVERNOR_ROLE, _address),
            'NeverminedConfig: Only governor'
        );
        _;
    }    
    
}

