// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ISignerProvider {
    function getSigner() external view returns (address);
}

