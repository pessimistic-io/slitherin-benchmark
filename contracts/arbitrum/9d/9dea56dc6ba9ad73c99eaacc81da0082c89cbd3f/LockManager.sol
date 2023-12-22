// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
pragma solidity 0.8.17;

import "./IIdentity.sol";
import "./ILockManager.sol";
import "./SafeCast.sol";

contract LockManager is ILockManager {
    using SafeCast for uint256;

    uint256 internal immutable _lockPeriod;

    struct Lock {
        address locker;
        uint64 expireAt;
    }

    mapping(address => Lock) internal _locks;

    modifier onlyModule(address identity) {
        require(
            IIdentity(identity).isModuleEnabled(msg.sender),
            "LM: caller must be an enabled module"
        );
        _;
    }

    modifier onlyLocker(address identity) {
        require(
            msg.sender == _locks[identity].locker,
            "LM: caller must be the locker"
        );
        _;
    }

    modifier onlyWhenIdentityLocked(address identity) {
        require(_isIdentityLocked(identity), "LM: identity must be locked");
        _;
    }

    modifier onlyWhenIdentityUnlocked(address identity) {
        require(!_isIdentityLocked(identity), "LM: identity must be unlocked");
        _;
    }

    constructor(uint256 lockPeriod) {
        _lockPeriod = lockPeriod;
    }

    function isIdentityLocked(address identity)
        external
        view
        override
        returns (bool)
    {
        return _isIdentityLocked(identity);
    }

    function getIdentityLockExpireAt(address identity)
        external
        view
        override
        returns (uint64)
    {
        return _locks[identity].expireAt;
    }

    function lockIdentity(address identity)
        external
        override
        onlyModule(identity)
        onlyWhenIdentityUnlocked(identity)
    {
        uint64 expireAt = (block.timestamp + _lockPeriod).toUint64();

        _setLock(identity, msg.sender, expireAt);

        emit IdentityLocked(identity, msg.sender, expireAt);
    }

    function unlockIdentity(address identity)
        external
        override
        onlyModule(identity)
        onlyLocker(identity)
        onlyWhenIdentityLocked(identity)
    {
        _setLock(identity, address(0), 0);

        emit IdentityUnlocked(identity);
    }

    function _isIdentityLocked(address identity) internal view returns (bool) {
        return block.timestamp.toUint64() < _locks[identity].expireAt;
    }

    function _setLock(
        address identity,
        address locker,
        uint64 expireAt
    ) internal {
        _locks[identity] = Lock(locker, expireAt);
    }
}

