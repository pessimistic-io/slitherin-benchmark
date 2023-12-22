//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ITGEVault {
    function donate(uint256 amount) external;

    function withdraw() external;
}

