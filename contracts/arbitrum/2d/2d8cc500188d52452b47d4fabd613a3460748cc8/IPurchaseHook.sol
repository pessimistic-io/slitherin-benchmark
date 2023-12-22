// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPurchaseHook {
    function setSigner(address lock, address signer) external;
}

