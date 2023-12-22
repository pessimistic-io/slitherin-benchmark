// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {decodeExecuteCallOpCalldata} from "./DecodeUtils.sol";
import {ECDSA} from "./ECDSA.sol";
import {UserOperation, ISessionValidationModule} from "./ISessionValidationModule.sol";
import {MerkleProof} from "./MerkleProof.sol";

contract AddressValidationModule is ISessionValidationModule {
    /**
     * @dev validates if the _op (UserOperation) matches the SessionKey permissions
     * and that _op has been signed by this SessionKey
     * Please mind the decimals of your exact token when setting maxAmount
     * @param _op User Operation to be validated.
     * @param _userOpHash Hash of the User Operation to be validated.
     * @param _sessionKeyData SessionKey data, that describes sessionKey permissions
     * @param _sessionKeySignature Signature over the the _userOpHash.
     * @return true if the _op is valid, false otherwise.
     */
    function validateSessionUserOp(
        UserOperation calldata _op,
        bytes32 _userOpHash,
        bytes calldata _sessionKeyData,
        bytes calldata _sessionKeySignature
    ) external pure override returns (bool) {
        revert("AddressValidationModule: Not Implemented");
    }

    /**
     * @dev validates that the call (destinationContract, callValue, funcCallData)
     * complies with the Session Key permissions represented by sessionKeyData
     * @param destinationContract address of the contract to be called
     * @param callValue value to be sent with the call
     * @param _funcCallData the data for the call. is parsed inside the SVM
     * @param _sessionKeyData SessionKey data, that describes sessionKey permissions
     */
    function validateSessionParams(
        address destinationContract,
        uint256 callValue,
        bytes calldata _funcCallData,
        bytes calldata _sessionKeyData,
        bytes calldata _callSpecificData
    ) external virtual override returns (address) {
        bytes32 dstRoot = abi.decode(_sessionKeyData[20:], (bytes32));

        bytes32[] memory validDstProof = abi.decode(
            _callSpecificData,
            (bytes32[])
        );

        // construct leaf for dst
        bytes32 dstLeaf = bytes32(uint256(uint160(destinationContract)));

        bool dstVerified = MerkleProof.verify(validDstProof, dstRoot, dstLeaf);

        if (!dstVerified) revert("AddressValidationModule: !dst");

        return address(bytes20(_sessionKeyData[:20]));
    }
}

