// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Right, Term, IAgreementManager} from "./Right.sol";
import {IGrant} from "./IGrant.sol";

import {IERC165} from "./interfaces_IERC165.sol";

/// @notice Agreement Term holds tokens claimable by the agreement owner.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/Grant.sol)
abstract contract Grant is Right, IGrant {
    /// @dev Storage of Grant Terms by Manager Contract and Agreement ID
    /// Only set at terms creation
    mapping(IAgreementManager => mapping(uint256 => GrantData)) public grantData;

    /// @dev Storage of this contract's token balance per Agreement
    mapping(IAgreementManager => mapping(uint256 => uint256)) public override tokenBalance;

    function _afterTermResolved(IAgreementManager manager, uint256 tokenId) internal virtual override {
        delete tokenBalance[manager][tokenId];
        delete grantData[manager][tokenId];

        super._afterTermResolved(manager, tokenId);
    }

    /// @inheritdoc IGrant
    function claim(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 amount
    ) public virtual override {
        if (manager.expired(tokenId)) revert Term__Expired();
        if (msg.sender != manager.ownerOf(tokenId)) revert Term__NotTokenOwner(msg.sender);
        if (amount > claimable(manager, tokenId)) revert Grant__InsufficientClaimable();

        tokenBalance[manager][tokenId] = tokenBalance[manager][tokenId] - amount;
        emit Claimed(manager, tokenId, amount);

        _claim(manager, tokenId, amount);
    }

    function _claim(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 amount
    ) internal virtual;

    function claimable(IAgreementManager manager, uint256 tokenId) public view virtual override returns (uint256) {
        // Total eligible amount
        uint256 grantAmount = grantData[manager][tokenId].amount;
        uint256 claimableUpTo = (manager.constraintStatus(tokenId) * grantAmount) / 100 ether;
        // Adjust for previously claimed amount
        return claimableUpTo - (grantAmount - tokenBalance[manager][tokenId]);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(Term, IERC165) returns (bool) {
        return interfaceId == type(IGrant).interfaceId || super.supportsInterface(interfaceId);
    }
}

