// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {decodeExecuteCallOpCalldata} from "./DecodeUtils.sol";
import {ECDSA} from "./ECDSA.sol";
import {UserOperation, ISessionValidationModule} from "./ISessionValidationModule.sol";
import {MerkleProof} from "./MerkleProof.sol";

contract ERC20ApprovalSessionValidationModule is ISessionValidationModule {
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
        revert("ERC20ASV: Not Implemented");
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
        (bytes32 tokenRoot, bytes32 spenderRoot) = abi.decode(
            _sessionKeyData[20:],
            (bytes32, bytes32)
        );

        (
            bytes32[] memory validTokensProof,
            bytes32[] memory validSpenderProof
        ) = abi.decode(_callSpecificData, (bytes32[], bytes32[]));

        if (callValue > 0) {
            revert("ERC20ASV: Non Zero Call Value");
        }

        // bytes (bytes4 selector + padded address of 32 bytes + uint256 of 32 bytes + offset of bytes32 + length of bytes32 + bytes4 of selector) i.e. 4+32+32+32+32 = 132 to 132+4 = 136
        bytes4 selector = bytes4(_funcCallData[0:4]);

        // bytes (bytes4 selector + padded address of 32 bytes + uint256 of 32 bytes + offset of bytes32 + length of bytes32 + bytes4 of selector) i.e. 4+32+32+32+32+4 = 136 to end
        bytes calldata data = _funcCallData[4:];

        if (selector != IERC20.approve.selector) {
            revert("ERC20ASV: selector mismatch");
        }

        // given: _calldata is of approval type, because this module was specified for validation
        (address spender, ) = abi.decode(data, (address, uint256));

        if (
            !MerkleProof.verify(
                validTokensProof,
                tokenRoot,
                bytes32(uint256(uint160(destinationContract)))
            ) ||
            !MerkleProof.verify(
                validSpenderProof,
                spenderRoot,
                bytes32(uint256(uint160(spender)))
            )
        ) {
            revert("ERC20ASV: spender or token not allowed");
        }

        return address(bytes20(_sessionKeyData[:20]));
    }
}

