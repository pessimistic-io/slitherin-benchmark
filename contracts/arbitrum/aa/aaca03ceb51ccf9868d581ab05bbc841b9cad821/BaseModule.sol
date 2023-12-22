// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
pragma solidity 0.8.17;

import "./ILockManager.sol";
import "./Address.sol";

contract BaseModule {
    using Address for address;

    ILockManager internal immutable _lockManager;

    constructor(address lockManager) {
        require(
            lockManager.isContract(),
            "BM: lock manager must be an existing contract address"
        );

        _lockManager = ILockManager(lockManager);
    }

    modifier onlySelf() {
        require(_isSelf(msg.sender), "BM: caller must be myself");
        _;
    }

    modifier onlyWhenIdentityUnlocked(address identity) {
        require(!_isIdentityLocked(identity), "BM: identity must be unlocked");
        _;
    }

    function _isSelf(address addr) internal view returns (bool) {
        return addr == address(this);
    }

    function _isIdentityLocked(address identity) internal view returns (bool) {
        return _lockManager.isIdentityLocked(identity);
    }

    function ping() external view onlySelf {}
}

