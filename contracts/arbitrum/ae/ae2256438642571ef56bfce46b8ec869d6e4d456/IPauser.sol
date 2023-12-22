// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

interface IPauser {
    event Paused(address sender);

    function pause() external;

    event Unpaused(address sender);

    function unpause() external;
}

