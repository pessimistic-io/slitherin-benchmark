// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./VerifierInfo.sol";
import "./Initializable.sol";
import "./Ownable.sol";
import "./Base64.sol";

interface IDKIMManager {
    function dkim(bytes memory name) external view returns (bytes memory);
}

interface IProofVerifier {
    function verifyProof(
            uint[2] memory a,
            uint[2][2] memory b,
            uint[2] memory c,
            uint[] memory input
        ) external view returns (bool r);
}

interface IRSAVerify {
    function pkcs1Sha256Verify(
        bytes32 _sha256,
        bytes memory _s, bytes memory _e, bytes memory _m
    ) external view returns (uint);
}


contract DKIMVerifier is Initializable, Ownable {
    address public dkimManager;
    address public proofVerifier;
    address public rsaVerify;
    
    function setDKIMManger(address _dkimManager) public onlyOwner {
        require(_dkimManager != address(0), "invalid dkimManager");
        dkimManager = _dkimManager;
    }

    function setProofVerifier(address _proofVerifier) public onlyOwner {
        require(_proofVerifier != address(0), "invalid dkimVerifier");
        proofVerifier = _proofVerifier;
    }

    function setRsaVerify(address _rsaVerify) public onlyOwner {
        require(_rsaVerify != address(0), "invalid rsaVerify");
        rsaVerify = _rsaVerify;
    }

    function initialize(address _dkimManager, address _proofVerifier, address _rsaVerify) external initializer {
        _transferOwnership(_msgSender());
        setDKIMManger(_dkimManager);
        setProofVerifier(_proofVerifier);
        setRsaVerify(_rsaVerify);
    }

    function verifier(
        address publicKey,
        bytes32 hmua,
        VerifierInfo calldata info
    ) external view {
        bytes memory modulus = IDKIMManager(dkimManager).dkim(info.ds);
        require(modulus.length != 0, "Not find modulus!");

        uint[] memory input = getInput(hmua, info.bh, info.base);
        //ZKP Verifier
        require(IProofVerifier(proofVerifier).verifyProof(info.a, info.b, info.c, input), "Invalid Proof");

        //bh(bytes) == base64(sha1/sha256(Canon-body))
        require(equalBase64(info.bh, info.body), "bh != sha(body)");

        //Operation ∈ Canon-body
        require(containsAddress(publicKey, info.body), "no pubkey in body");

        //b == RSA(base)
        require(verifyRsa(info.base, info.rb, info.e, modulus), "b != rsa(base)");
    }

    function getInput(
        bytes32 hmua,
        bytes memory bh,
        bytes32 base
    ) public pure returns (uint[] memory) {
        require(bh.length == 44, "wrong bh");
        uint[] memory output = new uint[](108);
        uint index = 0;
        for (uint i = 0; i < 32; i++) {
            output[index++] = uint(uint8(hmua[i]));
        }
        for (uint i = 0; i < bh.length; i++) {
            output[index++] = uint(uint8(bh[i]));
        }
        for (uint i = 0; i < 32; i++) {
            output[index++] = uint(uint8(base[i]));
        }
        return output;
    }

    function verifyRsa(bytes32 base, bytes memory rb, bytes memory e, bytes memory modulus) public view returns (bool) {
        uint result = IRSAVerify(rsaVerify).pkcs1Sha256Verify(base, rb, e, modulus);
        return result == 0;
    }

    function equalBase64(bytes memory bh, bytes memory body) public pure returns (bool) {
        return keccak256(bh) == keccak256(bytes(Base64.encode(abi.encodePacked(sha256(body)))));
    }


    function toAsciiBytes(address x) internal pure returns (bytes memory) {
        bytes memory s = new bytes(40);
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2**(8*(19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2*i] = char(hi);
            s[2*i+1] = char(lo);            
        }
        return s;
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }

    function containsAddress(address publicKey, bytes memory body) public pure returns (bool) {
        return contains(toAsciiBytes(publicKey), body);
    }

    function contains(bytes memory whatBytes, bytes memory whereBytes) public pure returns (bool) {
        if (whereBytes.length < whatBytes.length) {
            return false;
        }

        bool found = false;
        for (uint i = 0; i <= whereBytes.length - whatBytes.length; i++) {
            bool flag = true;
            for (uint j = 0; j < whatBytes.length; j++)
                if (whereBytes [i + j] != whatBytes [j]) {
                    flag = false;
                    break;
                }
            if (flag) {
                found = true;
                break;
            }
        }
        return found;
    }
}

