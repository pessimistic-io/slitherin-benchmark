// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./ECDSA.sol";

abstract contract SignatureLens is Ownable {

    struct Signature {
        uint256 nonce;
        uint256 deadline;
        bytes s;
    }

    event ResetSigner(address oldSigner, address newSigner);

    address private _signer;
    mapping(address =>uint256) private _signerNonce;
    mapping(bytes =>address) private _sigOperator;

    constructor (address signer) {
        require(signer != address(0),"Constructor: signer is the zero address");
        _signer = signer;
    }

    function signer() public view returns(address){
        return _signer;
    }

    function signerNonce(address user)public view returns(uint256){
        return _signerNonce[user];
    }

    function sigOperator(bytes memory s) public view returns(address){
        return _sigOperator[s];
    }

    function resetSigner(address signer) external onlyOwner{
        require(signer != address(0), "ResetSigner: signer is the zero address");
        address oldSigner = _signer;
        _signer = signer;

        emit ResetSigner(oldSigner, signer);
    }

    function verifySignature(string memory functionSelector, Signature calldata signature) internal virtual returns(bool) {
        bytes32 params = keccak256(abi.encodePacked("0x0000000000000000000000000000000000000000"));
        return verifySignature(functionSelector, params, signature);
    }

    function verifySignature(string memory functionSelector, bytes32 params, Signature calldata signature) internal virtual returns(bool) {
        uint256 _nonce = signature.nonce;
        uint256 _deadline = signature.deadline;
        bytes memory _s= signature.s;

        uint256 nonce = signerNonce(msg.sender);
        require(_nonce == nonce, "Illegal nonce");
        require(block.timestamp <= _deadline, "Out of time");
        require(sigOperator(_s) == address(0), "Sig is exist");

        address signer = resolveSignature(functionSelector, params, msg.sender, signature);
        _signerNonce[msg.sender] = nonce +1;
        _sigOperator[_s] = msg.sender;

        return signer != address(0) && signer == _signer;
    }

    function resolveSignature(string memory functionSelector, bytes32 params, address user, Signature calldata signature) private pure returns(address) {
        uint256 _nonce = signature.nonce;
        uint256 _deadline = signature.deadline;
        bytes calldata _s = signature.s;

        bytes32 hash = keccak256(abi.encodePacked(functionSelector, params, user, _nonce, _deadline));
        bytes32 message = ECDSA.toEthSignedMessageHash(hash);
        return ECDSA.recover(message, _s);
    }
}

