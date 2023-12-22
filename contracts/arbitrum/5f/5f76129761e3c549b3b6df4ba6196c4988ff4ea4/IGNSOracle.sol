// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IGNSOracle {
    function getAuthorizationStatus(address) external view returns (bool);

    function owner() external view returns (address);
}

