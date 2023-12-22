// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

interface IVault {
    function isAutoCompounded(uint256) external view returns (bool);

    function updatePosition(uint256) external;
}

