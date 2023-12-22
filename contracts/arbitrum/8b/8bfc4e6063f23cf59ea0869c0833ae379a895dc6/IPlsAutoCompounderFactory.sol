// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { CompounderDetails } from "./Structs.sol";
import { IAccessControl } from "./AccessControl.sol";

interface IPlsAutoCompounderFactory is IAccessControl {
    function domainSeparator() external view returns (bytes32);

    function plsAutoCompounderRouter() external view returns (address);

    function serviceFeeTaker() external view returns (address);

    function nonce() external view returns (uint256);

    function compoundersPaused() external view returns (bool);

    function serviceCharge() external view returns (uint16);

    function getAutocompounder(address user) external view returns (CompounderDetails memory);

    function getAllCompounders() external view returns (address[] memory);

    function predictDeterministicAddress(bytes32 salt) external view returns (address predicted);

    function setRouter(address router) external;

    function setServiceFeeTaker(address serviceFeeTaker) external;

    function modifyServiceCharge(uint16 serviceCharge) external;

    function createAutoCompounder(bytes memory sig, bytes32 salt, uint48 deadline) external;

    function createAutoCompounders(
        address[] memory users_,
        bytes[] memory sigs,
        bytes32[] memory salts,
        uint48 deadline
    ) external;
}

