// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <0.9.0;

import "./Ownable.sol";
import "./ECDSA.sol";

contract SignatureChecker is Ownable {
    using ECDSA for bytes32;
    address public validatorAddress;
    bool public checkSignatureFlag;

    constructor(){
        validatorAddress = 0xC47Ac3dD8b3fCd13C21D567D641A74b7272d5f78;
        checkSignatureFlag = true;
    }

    function setCheckSignatureFlag(bool newFlag) external onlyOwner {
        checkSignatureFlag = newFlag;
    }

    function setValidatorAddress(address _validatorAddress) external onlyOwner{
        validatorAddress = _validatorAddress;
    }

    function getSigner(bytes32 signedHash, bytes memory signature) public pure returns (address){
        return signedHash.toEthSignedMessageHash().recover(signature);
    }

    function checkSignature(bytes32 signedHash, bytes memory signature) public view returns (bool) {
        return getSigner(signedHash, signature) == validatorAddress;
    }

}
