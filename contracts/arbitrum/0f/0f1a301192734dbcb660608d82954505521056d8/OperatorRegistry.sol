// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

import {EnumerableSet} from "./EnumerableSet.sol";
import {ECDSA} from "./ECDSA.sol";
import {MessageHashUtils} from "./MessageHashUtils.sol";
import {IOperatorRegistry} from "./IOperatorRegistry.sol";

/// @dev We use custom EIP712 implementation (not OZ), because we don't need full domain info
contract OperatorRegistry is IOperatorRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    address public constant ALL = address(0xa11);
    bytes32 constant APPROVE_OPERATOR_SELECTOR =
        keccak256(
            "ApproveOperator(address user,address operator,address forAddress,uint256 nonce)"
        );

    bytes32 immutable DOMAIN_SEPARATOR_COMMON;
    bytes32 immutable DOMAIN_SEPARATOR_CHAIN_SPECIFIC;

    mapping(address => uint256) public nonce;
    mapping(address user => mapping(address operator => EnumerableSet.AddressSet forAddresses)) _approvals;

    event OperatorApprovalChanged(
        address indexed user,
        address indexed operator,
        address indexed forAddress,
        bool approved
    );

    error AlreadyApproved(address user, address operator, address forAddress);
    error NotApproved(address user, address operator, address forAddress);
    error InvalidSignature();

    constructor() {
        DOMAIN_SEPARATOR_COMMON = keccak256(
            abi.encode(
                keccak256("EIP712Domain(address verifyingContract)"),
                address(this)
            )
        );
        DOMAIN_SEPARATOR_CHAIN_SPECIFIC = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(uint256 chainId,address verifyingContract)"
                ),
                block.chainid,
                address(this)
            )
        );
    }

    function approveOperator(address operator, address forAddress) external {
        _approveOperator(msg.sender, operator, forAddress);
    }

    function approveOperatorWithPermit(
        address user,
        address operator,
        address forAddress,
        uint256 chainId,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            _getDomainSeparator(chainId),
            keccak256(
                // solhint-disable-next-line func-named-parameters
                abi.encode(
                    APPROVE_OPERATOR_SELECTOR,
                    user,
                    operator,
                    forAddress,
                    nonce[user]++
                )
            )
        );
        address recoveredAddress = ECDSA.recover(digest, v, r, s);
        if (recoveredAddress != user) {
            revert InvalidSignature();
        }

        _approveOperator(user, operator, forAddress);
    }

    function removeOperator(address operator, address forAddress) external {
        bool removed = _approvals[msg.sender][operator].remove(forAddress);
        if (!removed) {
            revert NotApproved(msg.sender, operator, forAddress);
        }
        emit OperatorApprovalChanged(msg.sender, operator, forAddress, false);
    }

    function isOperatorApprovedForAddress(
        address user,
        address operator,
        address forAddress
    ) external view returns (bool isApproved) {
        return
            _approvals[user][operator].contains(ALL) ||
            _approvals[user][operator].contains(forAddress);
    }

    function _approveOperator(
        address user,
        address operator,
        address forAddress
    ) internal {
        if (_approvals[user][operator].contains(ALL))
            revert AlreadyApproved(user, operator, forAddress);

        bool added = _approvals[user][operator].add(forAddress);
        if (!added) {
            revert AlreadyApproved(user, operator, forAddress);
        }

        emit OperatorApprovalChanged(user, operator, forAddress, true);
    }

    function _getDomainSeparator(
        uint256 chainId
    ) internal view returns (bytes32 domainSeparator) {
        if (chainId == 0) {
            domainSeparator = DOMAIN_SEPARATOR_COMMON;
        } else if (chainId == block.chainid) {
            domainSeparator = DOMAIN_SEPARATOR_CHAIN_SPECIFIC;
        }
    }
}

