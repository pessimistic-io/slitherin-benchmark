// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMellowToken {
    function isReplaceable(address) external view returns (bool);

    function equals(address) external view returns (bool);
}

