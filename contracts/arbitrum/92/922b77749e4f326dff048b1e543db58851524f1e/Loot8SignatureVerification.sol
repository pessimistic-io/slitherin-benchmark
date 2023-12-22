// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import "./ILoot8SignatureVerification.sol";

import "./Counters.sol";
import "./ECDSA.sol";
import "./EIP712.sol";

contract Loot8SignatureVerification is ILoot8SignatureVerification, EIP712 {

    using ECDSA for bytes32;

    using Counters for Counters.Counter;

    // Mapping Signers address => A nonce counter for signatures
    mapping(address => Counters.Counter) public nonces;

    bytes32 private constant _TYPEHASH =
        keccak256('LinkAccounts(address account,address loot8Account,string message,uint256 nonce)');

    constructor() EIP712('LOOT8', '1'){}

    function getSignerCurrentNonce(address _signer) public view returns(uint256){
        return nonces[_signer].current();
    }

    function verify(
        address _account, 
        address _loot8Account,
        string memory _message,
        bytes memory _signature
    ) public view returns (bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(_TYPEHASH, _account, _loot8Account, keccak256(abi.encodePacked(_message)), nonces[_account].current()))
        ).recover(_signature);
        return signer == _account;
    }

    function verifyAndUpdateNonce(
        address _account, 
        address _loot8Account,
        string memory _message,
        bytes memory _signature
    ) external returns (bool) {
        
        bool result = verify(_account, _loot8Account, _message, _signature);

        if(result) {
            nonces[_account].increment();
        }

        return result;
    }
    
}
