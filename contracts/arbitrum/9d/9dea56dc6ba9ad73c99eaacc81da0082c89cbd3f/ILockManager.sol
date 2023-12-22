// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

interface ILockManager {
    event IdentityLocked(
        address indexed identity,
        address indexed locker,
        uint64 expireAt
    );

    event IdentityUnlocked(address indexed identity);

    function isIdentityLocked(address identity) external view returns (bool);

    function getIdentityLockExpireAt(address identity)
        external
        view
        returns (uint64);

    function lockIdentity(address identity) external;

    function unlockIdentity(address identity) external;
}

