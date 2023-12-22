// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./SigCheckable.sol";
import "./WithAdmin.sol";

abstract contract Allocatable is SigCheckable, WithAdmin {
    mapping(address => bool) public signers;

    function addSigner(address _signer) external onlyOwner() {
        require(_signer != address(0), "Bad signer");
        signers[_signer] = true;
    }

    function removeSigner(address _signer) external onlyOwner() {
        require(_signer != address(0), "Bad signer");
        delete signers[_signer];
    }

    bytes32 constant AMOUNT_SIGNED_METHOD =
        keccak256("AmountSigned(bytes4 method, address token,address payee,address to,uint256 amount,uint64 expiry,bytes32 salt)");
    function amountSignedMessage(
			bytes4 method,
            address token,
            address payee,
            address to,
            uint256 amount,
			uint64 expiry,
            bytes32 salt)
    internal pure returns (bytes32) {
        return keccak256(abi.encode(
          AMOUNT_SIGNED_METHOD,
		  method,
          token,
          payee,
		  to,
          amount,
		  expiry,
          salt));
    }

    function verifyAmountUnique(
			bytes4 method,
            address token,
            address payee,
            address to,
            uint256 amount,
            bytes32 salt,
			uint64 expiry,
            bytes memory signature)
    internal {
		require(expiry == 0 || block.timestamp > expiry, "Allocatable: sig expired");
        bytes32 message = amountSignedMessage(method, token, payee, to, amount, expiry, salt);
        address _signer = signerUnique(message, signature);
        require(signers[_signer], "Allocatable: Invalid signer");
	}

    function verifyAmount(
			bytes4 method,
            address token,
            address payee,
            address to,
            uint256 amount,
            bytes32 salt,
			uint64 expiry,
            bytes memory signature)
    internal view {
		require(expiry == 0 || block.timestamp > expiry, "Allocatable: sig expired");
        bytes32 message = amountSignedMessage(method, token, payee, to, amount, expiry, salt);
        (,address _signer) = signer(message, signature);
        require(signers[_signer], "Allocatable: Invalid signer");
	}
}
