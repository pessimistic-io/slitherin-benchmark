// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Challenge} from "./Challenge.sol";
import {MessageHashUtils} from "./MessageHashUtils.sol";
import {ECDSA} from "./ECDSA.sol";
import {EIP712} from "./EIP712.sol";

contract S7 is Challenge, EIP712 {
    error S7__WrongSigner();
    error S7__NonceAlreadyUsed();

    bytes32 public constant TYPEHASH = keccak256("solveChallenge(uint256 nonce, string memory twitterHandle)");
    address private s_signer;

    mapping(uint256 => bool) private s_nonceUsed;

    constructor(address registry, address signer) Challenge(registry) EIP712("S7", "1") {
        s_signer = signer;
    }

    /*
     * CALL THIS FUNCTION
     * 
     * @param v - The v value of the signature
     * @param r - The r value of the signature
     * @param s - The s value of the signature
     * @param nonce - The nonce to use. Must be unique.
     * @param yourTwitterHandle - Your twitter handle. Can be a blank string.
     */
    function solveChallenge(uint8 v, bytes32 r, bytes32 s, uint256 nonce, string memory twitterHandle) external {
        bytes32 structHash = keccak256(abi.encode(TYPEHASH));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, v, r, s);
        if (isUsedNonce(nonce)) {
            revert S7__NonceAlreadyUsed();
        }
        if (signer != s_signer) {
            revert S7__WrongSigner();
        }
        _updateAndRewardSolver(twitterHandle);
    }

    function isUsedNonce(uint256 nonce) public view returns (bool) {
        return s_nonceUsed[nonce];
    }

    function getSigner() public view returns (address) {
        return s_signer;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////// The following are functions needed for the NFT, feel free to ignore. ///////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function attribute() external pure override returns (string memory) {
        return "Bridge Crosser";
    }

    function description() external pure override returns (string memory) {
        return "Section 7: Boss Bridge!";
    }

    function specialImage() external pure returns (string memory) {
        // This is b7.png
        return "ipfs://QmUQ59NUTj1wxwkgddx1DNFXMZebaBgfNC1VN2BufKgLnL";
    }
}

