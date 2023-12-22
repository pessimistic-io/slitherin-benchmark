// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable reason-string */
/* solhint-disable no-inline-assembly */

import "./BasePaymaster.sol";
import "./UserOperationLib.sol";
import "./ECDSA.sol";

/**
 * A sample paymaster that uses external service to decide whether to pay for the UserOp.
 * The paymaster trusts an external signer to sign the transaction.
 * The calling user must pass the UserOp to that external signer first, which performs
 * whatever off-chain verification before signing the UserOp.
 * Note that this signature is NOT a replacement for the account-specific signature:
 * - the paymaster checks a signature to agree to PAY for GAS.
 * - the account checks a signature to prove identity and account ownership.
 */
contract WhitelistPaymaster is BasePaymaster {
    using ECDSA for bytes32;
    using UserOperationLib for UserOperation;

    mapping(address => bool) public whitelist;

    uint256 private constant VALID_TIMESTAMP_OFFSET = 20;
    uint256 private constant SIGNATURE_OFFSET = 116;

    address public verifyingSigner;

    constructor(
        IEntryPoint _entryPoint,
        address _verifyingSigner
    ) BasePaymaster(_entryPoint) {
        verifyingSigner = _verifyingSigner;
    }

    function changeVerifyingSigner(address newSigner) external onlyOwner {
        verifyingSigner = newSigner;
    }

    function setWhitelistContract(
        address target,
        bool isAllowed
    ) external onlyOwner {
        whitelist[target] = isAllowed;
    }

    function setWhitelistContractBatch(
        address[] memory targets,
        bool isAllowed
    ) external onlyOwner {
        for (uint256 i = 0; i < targets.length; i++) {
            whitelist[targets[i]] = isAllowed;
        }
    }

    function _validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32,
        uint256
    )
        internal
        view
        override
        returns (bytes memory context, uint256 validationData)
    {
        (
            uint48 validUntil,
            uint48 validAfter,
            address target,
            bytes calldata signature
        ) = parsePaymasterAndData(userOp.paymasterAndData);

        require(whitelist[target], "target not whitelisted");
        //don't revert on signature failure: return SIG_VALIDATION_FAILED
        if (verifyingSigner != verify(target, signature)) {
            return ("", _packValidationData(true, validUntil, validAfter));
        }

        //no need for other on-chain validation: entire UserOp should have been checked
        // by the external service prior to signing it.
        return ("", _packValidationData(false, validUntil, validAfter));
    }

    function verify(
        address target,
        bytes calldata signature
    ) public pure returns (address) {
        bytes32 _hash = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encode(target))
        );

        return ECDSA.recover(_hash, signature);
    }

    function parsePaymasterAndData(
        bytes calldata paymasterAndData
    )
        public
        pure
        returns (
            uint48 validUntil,
            uint48 validAfter,
            address target,
            bytes calldata signature
        )
    {
        (validUntil, validAfter, target) = abi.decode(
            paymasterAndData[VALID_TIMESTAMP_OFFSET:SIGNATURE_OFFSET],
            (uint48, uint48, address)
        );

        signature = paymasterAndData[SIGNATURE_OFFSET:];
    }
}

