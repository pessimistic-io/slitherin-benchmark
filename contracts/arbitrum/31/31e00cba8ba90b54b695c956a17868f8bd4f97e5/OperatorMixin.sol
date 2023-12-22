// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

abstract contract OperatorMixin {
    error OperatorNotUnauthorized(address user, address operator);

    mapping(address user => mapping(address operator => bool isApproved)) operatorApproval;
    mapping(address => uint256) public operatorNonces;

    bytes32 public immutable DOMAIN_SEPARATOR;

    bytes32 constant DOMAIN_SEPARATOR_SIGNATURE_HASH =
        keccak256("EIP712Domain(string name,address verifyingContract)");
    string constant EIP191_PREFIX_FOR_EIP712_STRUCTURED_DATA = "\x19\x01";
    bytes32 constant OPERATOR_APPROVAL_SIGNATURE_HASH =
        keccak256(
            "operatorSetApproval(address user,address operator,bool approval, uint256 nonce)"
        );

    constructor(bytes memory operatorName) {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_SEPARATOR_SIGNATURE_HASH,
                keccak256(operatorName),
                address(this)
            )
        );
    }

    modifier operatorCheckApproval(address user) {
        _operatorCheckApproval(user);
        _;
    }

    function operatorSetApprovalWithPermit(
        address user,
        address operator,
        bool approval,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 digest = keccak256(
            abi.encodePacked(
                EIP191_PREFIX_FOR_EIP712_STRUCTURED_DATA,
                keccak256(
                    abi.encodePacked(
                        OPERATOR_APPROVAL_SIGNATURE_HASH,
                        user,
                        operator,
                        approval,
                        operatorNonces[user]++
                    )
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress == user, "Invalid signature");

        operatorApproval[user][operator] = approval;
        // emit OperatorApproved
    }

    function _operatorCheckApproval(address user) internal view {
        if (user != msg.sender && !operatorApproval[user][msg.sender]) {
            revert OperatorNotUnauthorized(user, msg.sender);
        }
    }
}

