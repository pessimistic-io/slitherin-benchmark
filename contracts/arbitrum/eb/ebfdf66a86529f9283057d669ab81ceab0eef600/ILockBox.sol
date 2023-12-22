// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ILockBox {
    function lockAmount(address, address, uint256) external;
    function unlockAmount(address, address, uint256) external;
    function unlockAmountTo(address, address, address, uint256) external;
    function getLockedAmount(address, address)
        external
        view
        returns (uint256);
    function hasLockedAmount(address, address, uint256)
        external
        view
        returns(bool);
}

