// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IVariableRateTransfers.sol";
import "./ChainUtils.sol";

contract SigUtils {
    bytes32 private constant DOMAIN_SEPARATOR =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    bytes32 private constant TRANSFER_TYPEHASH =
        keccak256(
            "Transfer(string invoiceId,address from,address to,address token,uint256 amount,bool usd)"
        );

    // TODO set in initialize fxn?
    string public constant NAME = "LoopVariableRatesContract";
    string public constant VERSION = "1";

    function _generateDigest(
        IVariableRateTransfers.Transfer calldata transfer_,
        address contract_
    ) internal view returns (bytes32 digest) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_SEPARATOR,
                keccak256(bytes(NAME)),
                keccak256(bytes(VERSION)),
                ChainUtils.getChainId(),
                contract_
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_TYPEHASH,
                keccak256(bytes(transfer_.invoiceId)),
                transfer_.from,
                transfer_.to,
                transfer_.token,
                transfer_.amount,
                transfer_.usd
            )
        );

        digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
    }

    function _getSigner(
        IVariableRateTransfers.Transfer calldata transfer_,
        IVariableRateTransfers.Signature calldata signature_
    ) internal view returns (address signer) {
        bytes32 digest = _generateDigest(transfer_, address(this));
        signer = ecrecover(digest, signature_.v, signature_.r, signature_.s);
    }
}

