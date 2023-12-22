// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract OperatorMixin {
    event ActionRequested(bytes data);

    error OnlyEOA();
    error OperatorNotAuthorized(address user, address operator);

    mapping(address user => mapping(address operator => bool isApproved)) operatorApproval;
    mapping(address => uint256) public operatorNonces;

    string constant EIP191_PREFIX_FOR_EIP712_STRUCTURED_DATA = "\x19\x01";
    bytes32 constant OPERATOR_APPROVAL_SIGNATURE_HASH =
        keccak256(
            "OperatorSetApproval(address user,address operator,bool approval,uint256 nonce)"
        );
    bytes32 constant DOMAIN_SEPARATOR =
        keccak256(abi.encode(keccak256("EIP712Domain()")));

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
        require(recoveredAddress == user, "Invalid signature");

        operatorApproval[user][operator] = approval;
    }

    function _requestForAction(bytes memory data) internal {
        if (msg.sender != tx.origin) {
            revert OnlyEOA();
        }
        emit ActionRequested(data);
    }

    function _operatorCheckApproval(address user) internal view {
        if (user != msg.sender && !operatorApproval[user][msg.sender]) {
            revert OperatorNotAuthorized(user, msg.sender);
        }
    }
}

