// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./GnosisSafeProxyFactory.sol";
import "./GnosisSafe.sol";
import "./ISignatureValidator.sol";
import "./Module.sol";
import {DefaultCallbackHandler} from "./DefaultCallbackHandler.sol";

/// @title Gnosis Utils
/// @author Chain Labs
/// @notice utility function for scheduler to interact with Gnosis contracts
contract GnosisUtils is ISignatureValidator {
    /// @notice Domain Separator, currently all domain have same typehash
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH =
        0x7a9f5b2bf4dbb53eb85e012c6094a3d71d76e5bfe821f44ab63ed59311264e35;
    
    /// @notice message type hash, currently all domains have same message typehash
    bytes32 private constant MSG_TYPEHASH =
        0xa1a7ad659422d5fc08fdc481fd7d8af8daf7993bc4e833452b0268ceaab66e5d;
    
    /// @notice nonce to be used when setting up gnosis safe
    /// @return integer value 0
    uint256 public constant setupNonce = 0;

    /// @notice generate signature
    /// @param _data data to be signed
    /// @param _safe address of safe for which the signature has to be generated
    /// @return signature
    function _generateSignature(bytes memory _data, GnosisSafe _safe)
        internal
        view
        returns (bytes memory signature)
    {
        // get contractTransactionHash from gnosis safe
        bytes32 hash = _safe.getTransactionHash(
            address(_safe),
            0,
            _data,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            address(0),
            setupNonce
        );

        bytes memory paddedAddress = bytes.concat(
            bytes12(0),
            bytes20(address(this))
        );
        bytes memory messageHash = _encodeMessageHash(hash);

        // generate signature and add it to approvedSignatures mapping
        signature = bytes.concat(
            paddedAddress,
            bytes32(uint256(65)),
            bytes1(0),
            bytes32(uint256(messageHash.length)),
            messageHash
        );
    }

    /// @notice encode message for signature
    /// @param message message to be encoded
    /// @return encoded message
    function _encodeMessageHash(bytes32 message)
        private
        pure
        returns (bytes memory)
    {
        bytes32 safeMessageHash = keccak256(abi.encode(MSG_TYPEHASH, message));
        return
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x23),
                keccak256(
                    abi.encode(DOMAIN_SEPARATOR_TYPEHASH, safeMessageHash)
                )
            );
    }

    /// @notice always return true to signature validation
    function isValidSignature(bytes memory, bytes memory)
        public
        pure
        override
        returns (bytes4)
    {
        return EIP1271_MAGIC_VALUE;
    }

    /// @notice create safe
    /// @param _owners array of gnosis safe owners
    /// @param _safeFactory address of safe factory
    /// @param _singleton address of safe singleton
    /// @param _fallbackHandler address of default fallback handler to ensure assets can be received
    /// @return safe address of deployed safe
    function _createSafe(
        address[] memory _owners,
        address _safeFactory,
        address _singleton,
        address _fallbackHandler
    ) internal returns (GnosisSafe safe) {
        bytes memory data = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            _owners,
            1,
            address(0),
            "",
            _fallbackHandler,
            address(0),
            0,
            address(0)
        );
        safe = GnosisSafe(
            payable(
                address(
                    GnosisSafeProxyFactory(_safeFactory).createProxy(
                        _singleton,
                        data
                    )
                )
            )
        );
    }

    /// @notice enable scheduler as a module of gnosis safe
    /// @param safe address of safe where the scheduler needs to be added as module
    function _enableModule(GnosisSafe safe) internal {
        bytes memory execData = abi.encodeWithSelector(
            safe.enableModule.selector,
            address(this)
        );
        // generate signature
        bytes memory temporarySignature = _generateSignature(execData, safe);

        // execute transaction to add module
        safe.execTransaction(
            address(safe),
            0,
            execData,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            temporarySignature
        );
    }

    /// @notice remove owner from gnosis safe
    /// @param safe address of safe whose owner needs to be removed
    /// @param _owners list of owners, with previous owner at index 0, and owner to be removed at index 1
    function _removeOwner(GnosisSafe safe, address[] memory _owners) internal {
        bytes memory execDataToRemoveOwner = abi.encodeWithSelector(
            safe.removeOwner.selector,
            _owners[0],
            _owners[1],
            1
        );
        // generate signature

        bytes memory temporarySignatureToRemoveOwner = _generateSignature(
            execDataToRemoveOwner,
            safe
        );

        safe.execTransaction(
            address(safe),
            0,
            execDataToRemoveOwner,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            temporarySignatureToRemoveOwner
        );
    }
}

