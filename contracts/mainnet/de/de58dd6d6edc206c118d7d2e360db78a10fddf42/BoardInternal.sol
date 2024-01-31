/*
 * This file is part of the Qomet Technologies contracts (https://github.com/qomet-tech/contracts).
 * Copyright (c) 2022 Qomet Technologies (https://qomet.tech)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
// SPDX-License-Identifier: GNU General Public License v3.0

pragma solidity 0.8.1;

import "./AddressSet.sol";
import "./CouncilLib.sol";
import "./Constants.sol";
import "./BoardStorage.sol";

/// @author Kam Amini <kam@arteq.io>
///
/// @notice Use at your own risk
library BoardInternal {

    event AdminAdd(address indexed account);
    event CreatorAdd(address indexed account);
    event ExecutorAdd(address indexed account);
    event FinalizerAdd(address indexed account);
    event AdminRemove(address indexed account);
    event CreatorRemove(address indexed account);
    event ExecutorRemove(address indexed account);
    event FinalizerRemove(address indexed account);

    modifier mustBeInitialized() {
        require(__s().initialized, "BI:NI");
        _;
    }

    function _initialize(
        address[] memory admins,
        address[] memory creators,
        address[] memory executors,
        address[] memory finalizers
    ) internal {
        require(!__s().initialized, "BI:AI");
        require(admins.length >= 3, "BI:NEA");
        require(creators.length >= 1, "BI:NEC");
        require(executors.length >= 1, "BI:NEE");
        for (uint256 i = 0; i < admins.length; i++) {
            address account = admins[i];
            if (AddressSetLib._addItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.ADMIN_SET_ID, account)) {
                emit AdminAdd(account);
            }
        }
        for (uint256 i = 0; i < creators.length; i++) {
            address account = creators[i];
            if (AddressSetLib._addItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.CREATOR_SET_ID, account)) {
                emit CreatorAdd(account);
            }
        }
        for (uint256 i = 0; i < executors.length; i++) {
            address account = executors[i];
            if (AddressSetLib._addItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.EXECUTOR_SET_ID, account)) {
                emit ExecutorAdd(account);
            }
        }
        for (uint256 i = 0; i < finalizers.length; i++) {
            address account = finalizers[i];
            if (AddressSetLib._addItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.FINALIZER_SET_ID, account)) {
                emit FinalizerAdd(account);
            }
        }
        __s().initialized = true;
    }

    function _isOperator(uint256 operatorType, address account) internal view returns (bool) {
        require(__isOperatorTypeValid(operatorType), "BI:INVOT");
        if (operatorType == ConstantsLib.OPERATOR_TYPE_ADMIN) {
            return AddressSetLib._hasItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.ADMIN_SET_ID, account);
        } else if (operatorType == ConstantsLib.OPERATOR_TYPE_CREATOR) {
            return AddressSetLib._hasItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.CREATOR_SET_ID, account);
        } else if (operatorType == ConstantsLib.OPERATOR_TYPE_EXECUTOR) {
            return AddressSetLib._hasItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.EXECUTOR_SET_ID, account);
        } else if (operatorType == ConstantsLib.OPERATOR_TYPE_FINALIZER) {
            return AddressSetLib._hasItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.FINALIZER_SET_ID, account);
        }
        return false;
    }

    function _getOperators(uint256 operatorType) internal view returns (address[] memory) {
        require(__isOperatorTypeValid(operatorType), "BI:INVOT");
        if (operatorType == ConstantsLib.OPERATOR_TYPE_ADMIN) {
            return AddressSetLib._getItems(ConstantsLib.SET_ZONE_ID, ConstantsLib.ADMIN_SET_ID);
        } else if (operatorType == ConstantsLib.OPERATOR_TYPE_CREATOR) {
            return AddressSetLib._getItems(ConstantsLib.SET_ZONE_ID, ConstantsLib.CREATOR_SET_ID);
        } else if (operatorType == ConstantsLib.OPERATOR_TYPE_EXECUTOR) {
            return AddressSetLib._getItems(ConstantsLib.SET_ZONE_ID, ConstantsLib.EXECUTOR_SET_ID);
        } else if (operatorType == ConstantsLib.OPERATOR_TYPE_FINALIZER) {
            return AddressSetLib._getItems(ConstantsLib.SET_ZONE_ID, ConstantsLib.FINALIZER_SET_ID);
        }
        return new address[](0);
    }

    function _addOperator(
        uint256 adminProposalId,
        uint256 operatorType,
        address account
    ) internal mustBeInitialized {
        require(__isOperatorTypeValid(operatorType), "BI:INVOT");
        CouncilLib._executeAdminProposal(address(this), msg.sender, adminProposalId);
        if (operatorType == ConstantsLib.OPERATOR_TYPE_ADMIN) {
            if (AddressSetLib._addItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.ADMIN_SET_ID, account)) {
                emit AdminAdd(account);
            }
        } else if (operatorType == ConstantsLib.OPERATOR_TYPE_CREATOR) {
            if (AddressSetLib._addItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.CREATOR_SET_ID, account)) {
                emit CreatorAdd(account);
            }
        } else if (operatorType == ConstantsLib.OPERATOR_TYPE_EXECUTOR) {
            if (AddressSetLib._addItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.EXECUTOR_SET_ID, account)) {
                emit ExecutorAdd(account);
            }
        } else if (operatorType == ConstantsLib.OPERATOR_TYPE_FINALIZER) {
            if (AddressSetLib._addItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.FINALIZER_SET_ID, account)) {
                emit FinalizerAdd(account);
            }
        }
    }

    function _removeOperator(
        uint256 adminProposalId,
        uint256 operatorType,
        address account
    ) internal mustBeInitialized {
        require(__isOperatorTypeValid(operatorType), "BI:INVOT");
        CouncilLib._executeAdminProposal(address(this), msg.sender, adminProposalId);
        if (operatorType == ConstantsLib.OPERATOR_TYPE_ADMIN) {
            if (AddressSetLib._removeItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.ADMIN_SET_ID, account)) {
                emit AdminRemove(account);
            }
        } else if (operatorType == ConstantsLib.OPERATOR_TYPE_CREATOR) {
            if (AddressSetLib._removeItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.CREATOR_SET_ID, account)) {
                emit CreatorRemove(account);
            }
        } else if (operatorType == ConstantsLib.OPERATOR_TYPE_EXECUTOR) {
            if (AddressSetLib._removeItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.EXECUTOR_SET_ID, account)) {
                emit ExecutorRemove(account);
            }
        } else if (operatorType == ConstantsLib.OPERATOR_TYPE_FINALIZER) {
            if (AddressSetLib._removeItem(
                ConstantsLib.SET_ZONE_ID, ConstantsLib.FINALIZER_SET_ID, account)) {
                emit FinalizerRemove(account);
            }
        }
    }

    function _makeFinalizer(address account) internal mustBeInitialized {
        // add the grant-token contract as a finalizer by default
        if (AddressSetLib._addItem(
            ConstantsLib.SET_ZONE_ID, ConstantsLib.FINALIZER_SET_ID, account)) {
            emit FinalizerAdd(account);
        }
    }

    function __isOperatorTypeValid(uint256 operatorType) private pure returns (bool) {
        return operatorType >= 1 && operatorType <= 4;
    }

    function __s() private pure returns (BoardStorage.Layout storage) {
        return BoardStorage.layout();
    }
}

