// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IMigratorChef {
    function migrate(address token) external returns (address);
}
