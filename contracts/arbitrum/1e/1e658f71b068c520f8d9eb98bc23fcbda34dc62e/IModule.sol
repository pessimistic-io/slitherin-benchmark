// SPDX-License-Identifier: LGPL-3.0-only

/// @title Module Interface - A contract that can pass messages to a Module Manager contract if enabled by that contract.
pragma solidity >=0.7.0 <0.9.0;

import "./Enum.sol";
import "./UserOperation.sol";

interface IModule {
    function exec(
        address avatar,
        address srcAddress,
        UserOperation calldata uo
    ) external returns (bool success);

    function nonces(address avatar) external view returns (uint256);

}
