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


