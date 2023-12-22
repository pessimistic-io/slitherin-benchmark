// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILoot8SignatureVerification {

    function getSignerCurrentNonce(address _signer) external view returns(uint256);

    function verify(
        address _account, 
        address _loot8Account,
        string memory _message,
        bytes memory _signature
    ) external view returns (bool);

    function verifyAndUpdateNonce(
        address _account, 
        address _loot8Account,
        string memory _message,
        bytes memory _signature
    ) external returns (bool);
    
}

