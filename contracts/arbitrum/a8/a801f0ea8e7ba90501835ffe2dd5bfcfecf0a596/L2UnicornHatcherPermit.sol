// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {EIP712} from "./EIP712.sol";
import {Ownable} from "./Ownable.sol";

import {ECDSA} from "./ECDSA.sol";

/**
 * @notice Unicorn Hatcher Permit
 */
abstract contract L2UnicornHatcherPermit is EIP712, Ownable {

    address public authorizer;

    bytes32 private constant _PERMIT_TYPEHASH = keccak256("Permit(address user,uint8 eSeries,uint256 nonce,uint256 deadline)");

    // user => uint256
    mapping(address => uint256) internal _nonces;

    constructor(address authorizer_) EIP712("L2UnicornHatcherPermit", "1") {
        authorizer = authorizer_;
    }

    function permit(address user_, uint8 eSeries_, uint256 deadline_, uint8 v_, bytes32 r_, bytes32 s_) public {
        require(block.timestamp <= deadline_, "L2UnicornHatcherPermit: expired deadline");
        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, user_, eSeries_, _nonces[user_]++, deadline_));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer_ = ECDSA.recover(hash, v_, r_, s_);
        require(signer_ == authorizer, "L2UnicornHatcherPermit: invalid signature");
    }

    function userNonces(address user_) public view returns (uint256) {
        return _nonces[user_];
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function setAuthorizer(address authorizer_) external onlyOwner {
        authorizer = authorizer_;
    }

}

