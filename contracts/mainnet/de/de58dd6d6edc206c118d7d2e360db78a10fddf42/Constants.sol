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

library ConstantsLib {

    uint256 constant public GRANT_TOKEN_ADMIN_ROLE =
        uint256(keccak256(bytes("GRANT_TOKEN_ADMIN_ROLE")));
    uint256 constant public FAST_TRANSFER_ELIGIBLE_ROLE =
        uint256(keccak256(bytes("FAST_TRANSFER_ELIGIBLE_ROLE")));
    bytes4 constant public GRANT_TOKEN_INTERFACE_ID = 0x8fd617ec;

    bytes32 public constant SET_ZONE_ID = bytes32(uint256(1));

    bytes32 public constant ADMIN_SET_ID = bytes32(uint256(1));
    bytes32 public constant CREATOR_SET_ID = bytes32(uint256(2));
    bytes32 public constant EXECUTOR_SET_ID = bytes32(uint256(3));
    bytes32 public constant FINALIZER_SET_ID = bytes32(uint256(4));

    uint256 public constant OPERATOR_TYPE_ADMIN = 1;
    uint256 public constant OPERATOR_TYPE_CREATOR = 2;
    uint256 public constant OPERATOR_TYPE_EXECUTOR = 3;
    uint256 public constant OPERATOR_TYPE_FINALIZER = 4;
}

