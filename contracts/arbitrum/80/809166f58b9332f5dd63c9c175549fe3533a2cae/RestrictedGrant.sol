// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Grant, IAgreementManager} from "./Grant.sol";
import {DelegatingGrant, GrantLock} from "./DelegatingGrant.sol";
import {AuthorizedShareGrant, IAuthorizedShareToken} from "./AuthorizedShareGrant.sol";

import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {ERC165Checker} from "./ERC165Checker.sol";

/// @notice Agreement Term grant that deposits all tokens to vault at creation.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/RestrictedGrant.sol)
contract RestrictedGrant is DelegatingGrant, AuthorizedShareGrant {
    using SafeERC20 for IERC20;

    function _createTerm(
        IAgreementManager manager,
        uint256 tokenId,
        bytes calldata data
    ) internal virtual override {
        GrantData memory data_ = abi.decode(data, (GrantData));
        checkTokenInterface(address(data_.token));
        if (data_.amount == 0) revert Term__ZeroValue();

        grantData[manager][tokenId] = data_;
        tokenBalance[manager][tokenId] = data_.amount;
        authTokenBalance[manager][tokenId] = 0;

        address deployedGrantLock = address(
            deployGrantLock(manager, tokenId, IAuthorizedShareToken(address(data_.token)).underlying())
        );

        // transfer amount
        data_.token.safeTransferFrom(manager.issuer(tokenId), address(this), data_.amount);
        // issue when created
        IAuthorizedShareToken(address(data_.token)).issueTo(deployedGrantLock, data_.amount);
    }

    function _settleTerm(IAgreementManager manager, uint256 tokenId) internal virtual override {
        uint256 balance = tokenBalance[manager][tokenId];
        GrantLock grantLockAddress = grantLock[manager][tokenId];

        // Settle remaining balance to token owner
        if (balance > 0) {
            grantLockAddress.withdraw(manager.ownerOf(tokenId), balance);
        }
    }

    function _cancelTerm(IAgreementManager manager, uint256 tokenId) internal virtual override {
        // Settle eligible balance to token owner
        // This prevents scams where an issuer receives payment, then cancels the agreement
        // More lenient (for the issuer) clawback provisions can be added as additional Terms
        uint256 claimAmount = claimable(manager, tokenId);
        uint256 remainingAmount = tokenBalance[manager][tokenId] - claimAmount;
        GrantLock grantLockAddress = grantLock[manager][tokenId];

        if (claimAmount > 0) {
            grantLockAddress.withdraw(manager.ownerOf(tokenId), claimAmount);
        }

        // Refund ineligible balance to issuer
        if (remainingAmount > 0) {
            grantLockAddress.withdraw(manager.issuer(tokenId), remainingAmount);
        }
    }

    function _afterTermResolved(IAgreementManager manager, uint256 tokenId) internal virtual override {
        delete authTokenBalance[manager][tokenId];

        super._afterTermResolved(manager, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Grant, AuthorizedShareGrant)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

