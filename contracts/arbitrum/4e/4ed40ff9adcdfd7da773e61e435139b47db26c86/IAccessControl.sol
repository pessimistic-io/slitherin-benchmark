// SPDX-License-Identifier: UNLICENSED

/* *
 * Copyright (c) 2021-2023 LI LI @ JINGTIAN & GONGCHENG.
 *
 * This WORK is licensed under ComBoox SoftWare License 1.0, a copy of which 
 * can be obtained at:
 *         [https://github.com/paul-lee-attorney/comboox]
 *
 * THIS WORK IS PROVIDED ON AN "AS IS" BASIS, WITHOUT 
 * WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED 
 * TO NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE. IN NO 
 * EVENT SHALL ANY CONTRIBUTOR BE LIABLE TO YOU FOR ANY DAMAGES.
 *
 * YOU ARE PROHIBITED FROM DEPLOYING THE SMART CONTRACTS OF THIS WORK, IN WHOLE 
 * OR IN PART, FOR WHATEVER PURPOSE, ON ANY BLOCKCHAIN NETWORK THAT HAS ONE OR 
 * MORE NODES THAT ARE OUT OF YOUR CONTROL.
 * */

pragma solidity ^0.8.8;

import "./RolesRepo.sol";

import "./IRegCenter.sol";
import "./IGeneralKeeper.sol";

interface IAccessControl {

    // ##################
    // ##   Event      ##
    // ##################

    event Init(
        address indexed owner,
        address indexed directKeeper,
        address regCenter,
        address indexed generalKeeper
    );

    event SetOwner(address indexed acct);

    event SetDirectKeeper(address indexed keeper);

    event SetRoleAdmin(bytes32 indexed role, address indexed acct);

    event LockContents();

    // ##################
    // ##    Write     ##
    // ##################

    function init(
        address owner,
        address directKeeper,
        address regCenter,
        address generalKeeper
    ) external;

    function setOwner(address acct) external;

    function setDirectKeeper(address keeper) external;

    function takeBackKeys(address target) external;

    function setRoleAdmin(bytes32 role, address acct) external;

    function grantRole(bytes32 role, address acct) external;

    function revokeRole(bytes32 role, address acct) external;

    function renounceRole(bytes32 role) external;

    function abandonRole(bytes32 role) external;

    function lockContents() external;

    // ##################
    // ##   Read I/O   ##
    // ##################

    function getOwner() external view returns (address);

    function getDK() external view returns (address);

    function isFinalized() external view returns (bool);

    function getRoleAdmin(bytes32 role) external view returns (address);

    function hasRole(bytes32 role, address acct) external view returns (bool);

}

