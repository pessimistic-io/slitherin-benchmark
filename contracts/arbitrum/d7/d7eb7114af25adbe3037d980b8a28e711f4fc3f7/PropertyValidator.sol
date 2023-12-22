// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./Ownable.sol";


contract PropertyValidator is Ownable {

    bytes4 public constant MAGIC_BYTES = this.validateProperty.selector;

    address public immutable ELEMENT_EX;

    mapping(address => bool) public signers;

    event AddSigner(address indexed signer);
    event RemoveSigner(address indexed signer);

    constructor(address elementEx) {
        ELEMENT_EX = elementEx;
    }

    function addSigner(address signer) external onlyOwner {
        require(signer != address(0), "invalid signer");
        require(!signers[signer], "signer is added");

        signers[signer] = true;
        emit AddSigner(signer);
    }

    function removeSigner(address signer) external onlyOwner {
        require(signers[signer], "signer is removed");

        signers[signer] = false;
        emit RemoveSigner(signer);
    }

    function validateProperty(
        address /* tokenAddress */,
        uint256 /* tokenId */,
        bytes32 orderHash,
        bytes calldata /* propertyData */,
        bytes calldata takerData
    ) external view returns(bytes4) {
        require(msg.sender == ELEMENT_EX, "validateProperty/unauthorized_caller");
        require(takerData.length == 69, "validateProperty/takerData_error");

        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 deadline;
        bytes32 validateHash;

        assembly {
            // takerData -> 32bytes[r] + 32bytes[s] + 1bytes[v] + 4bytes[deadline]
            r := calldataload(takerData.offset)
            s := calldataload(add(takerData.offset, 32))
            v := and(calldataload(add(takerData.offset, 33)), 0xff)
            deadline := and(calldataload(add(takerData.offset, 37)), 0xffffffff)

            let ptr := mload(0x40)  // free memory pointer
            mstore(ptr, orderHash)
            mstore(add(ptr, 0x20), deadline)
            validateHash := keccak256(ptr, 0x40)
        }

        require(block.timestamp < deadline, "validateProperty/deadline_reached");

        address signer = ecrecover(validateHash, v, r, s);
        require(signers[signer], "validateProperty/invalid_signer");

        return MAGIC_BYTES;
    }
}

