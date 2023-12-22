// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract OperatorMixin {
    event OperatorApprovalChanged(
        address indexed user,
        address indexed operator,
        bool approval
    );

    error InvalidSignature();
    error OperatorNotAuthorized(address user, address operator);

    string constant EIP191_PREFIX_FOR_EIP712_STRUCTURED_DATA = "\x19\x01";
    bytes32 constant OPERATOR_APPROVAL_SIGNATURE_HASH =
        keccak256(
            "OperatorSetApproval(address user,address operator,bool approval,uint256 nonce)"
        );
    bytes32 constant DOMAIN_SEPARATOR =
        keccak256(abi.encode(keccak256("EIP712Domain()")));

    mapping(address user => mapping(address operator => bool isApproved))
        public operatorApproval;
    mapping(address => uint256) public operatorNonces;

    modifier operatorCheckApproval(address user) {
        _operatorCheckApproval(user);
        _;
    }

    function operatorSetApproval(address operator, bool approval) external {
        _operatorSetApproval(msg.sender, operator, approval);
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
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
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
        if (recoveredAddress != user) {
            revert InvalidSignature();
        }
        _operatorSetApproval(user, operator, approval);
    }

    function _operatorSetApproval(
        address user,
        address operator,
        bool approval
    ) internal {
        operatorApproval[user][operator] = approval;
        emit OperatorApprovalChanged(user, operator, approval);
    }

    function _operatorCheckApproval(address user) internal view {
        if (user != msg.sender && !operatorApproval[user][msg.sender]) {
            revert OperatorNotAuthorized(user, msg.sender);
        }
    }
}

