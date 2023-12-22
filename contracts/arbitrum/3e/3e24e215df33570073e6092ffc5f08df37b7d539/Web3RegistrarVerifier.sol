// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./EIP712Upgradeable.sol";
import "./SignatureCheckerUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./LibWeb3Domain.sol";

contract Web3RegistrarVerifier is OwnableUpgradeable, EIP712Upgradeable {
    address public verifierAddress;

    function __Web3RegistrarVerifier_init_unchained(address _verifierAddress) internal onlyInitializing {
        __Ownable_init_unchained();
        __EIP712_init_unchained("Web3Registrar", "1");
        verifierAddress = _verifierAddress;
    }

    function verifyOrder(LibWeb3Domain.Order calldata order, bytes calldata signature) internal view {
        require(
            SignatureCheckerUpgradeable.isValidSignatureNow(
                verifierAddress,
                _hashTypedDataV4(LibWeb3Domain.getHash(order)),
                signature
            ),
            "invalid signature"
        );
    }

    function verifyOrder(LibWeb3Domain.SimpleOrder calldata order, bytes calldata signature) internal view {
        require(
            SignatureCheckerUpgradeable.isValidSignatureNow(
                verifierAddress,
                _hashTypedDataV4(LibWeb3Domain.getHash(order)),
                signature
            ),
            "invalid signature"
        );
    }

    function verifyReclaim(LibWeb3Domain.ReclaimNodeRequest calldata request, bytes calldata signature) internal view {
        require(
            SignatureCheckerUpgradeable.isValidSignatureNow(
                verifierAddress,
                _hashTypedDataV4(LibWeb3Domain.getHash(request)),
                signature
            ),
            "invalid signature"
        );
    }

    function setVerifierAddress(address newVerifierAddress) external onlyOwner {
        verifierAddress = newVerifierAddress;
    }

    uint256[49] private __gap;
}

