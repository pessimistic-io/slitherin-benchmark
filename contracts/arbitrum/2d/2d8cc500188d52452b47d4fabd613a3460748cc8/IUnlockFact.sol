// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;



interface IUnlockFact {
    function createUpgradeableLock(bytes memory data) external returns (address);

}
