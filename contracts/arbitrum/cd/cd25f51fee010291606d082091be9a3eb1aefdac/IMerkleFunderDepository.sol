// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IMerkleFunderDepository {
    error SenderNotMerkleFunder();

    error TransferUnsuccessful();

    function merkleFunder() external view returns (address);

    function owner() external view returns (address);

    function root() external view returns (bytes32);
}

