// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IOperatorRegistry} from "./IOperatorRegistry.sol";

contract OperatorMixin {
    IOperatorRegistry public immutable OPERATOR_REGISTRY;

    modifier operatorCheckApproval(address user) {
        _operatorCheckApproval(user);
        _;
    }

    constructor(address operatorRegistry) {
        OPERATOR_REGISTRY = IOperatorRegistry(operatorRegistry);
    }

    function _operatorCheckApproval(address user) internal view {
        if (user != msg.sender) {
            OPERATOR_REGISTRY.isOperatorApprovedForAddress(
                user,
                msg.sender,
                address(this)
            );
        }
    }
}

