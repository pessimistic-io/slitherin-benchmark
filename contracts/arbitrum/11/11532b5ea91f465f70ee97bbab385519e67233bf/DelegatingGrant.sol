// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Grant, IAgreementManager} from "./Grant.sol";
import {GrantLock, ShareTokenBase} from "./GrantLock.sol";

/// @notice Agreement Term grant with vault for tokens.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/DelegatingGrant.sol)
abstract contract DelegatingGrant is Grant {
    event GrantLocked(GrantLock grantLockContract);

    /// @dev set location of deployed grant lock contracts
    mapping(IAgreementManager => mapping(uint256 => GrantLock)) public grantLock;

    function deployGrantLock(
        IAgreementManager manager,
        uint256 tokenId,
        ShareTokenBase token
    ) internal virtual returns (GrantLock) {
        GrantLock deployedGrantLock = new GrantLock(manager.ownerOf(tokenId), token);
        // slither-disable-next-line reentrancy-events
        emit GrantLocked(deployedGrantLock);
        // slither-disable-next-line reentrancy-benign
        grantLock[manager][tokenId] = deployedGrantLock;

        return deployedGrantLock;
    }

    function _afterTermResolved(IAgreementManager manager, uint256 tokenId) internal virtual override {
        GrantLock lock = grantLock[manager][tokenId];
        delete grantLock[manager][tokenId];

        super._afterTermResolved(manager, tokenId);

        // Destroy lock contract
        lock.destroy(payable(manager.ownerOf(tokenId)));
    }

    function _claim(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 amount
    ) internal virtual override {
        grantLock[manager][tokenId].withdraw(manager.ownerOf(tokenId), amount);
    }
}

