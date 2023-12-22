// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Grant, IAgreementManager} from "./Grant.sol";
import {AuthorizedShareGrant, IAuthorizedShareToken} from "./AuthorizedShareGrant.sol";

import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {ERC165Checker} from "./ERC165Checker.sol";

/// @notice Agreement Term grant that issues shares directly to agreement owner.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/UnrestrictedGrant.sol)
contract UnrestrictedGrant is Grant, AuthorizedShareGrant {
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
        authTokenBalance[manager][tokenId] = data_.amount;

        // transfer amount
        data_.token.safeTransferFrom(manager.issuer(tokenId), address(this), data_.amount);
    }

    function _settleTerm(IAgreementManager manager, uint256 tokenId) internal virtual override {
        GrantData memory data = grantData[manager][tokenId];
        uint256 balance = tokenBalance[manager][tokenId];

        // Settle remaining balance to token owner
        if (balance > 0) {
            IAuthorizedShareToken(address(data.token)).issueTo(manager.ownerOf(tokenId), balance);
        }
    }

    function _cancelTerm(IAgreementManager manager, uint256 tokenId) internal virtual override {
        // Settle eligible balance to token owner
        // This prevents scams where an issuer receives payment, then cancels the agreement
        // More lenient (for the issuer) clawback provisions can be added as additional Terms
        uint256 claimAmount = claimable(manager, tokenId);
        GrantData memory data = grantData[manager][tokenId];
        uint256 remainingAmount = tokenBalance[manager][tokenId] - claimAmount;

        if (claimAmount > 0) {
            IAuthorizedShareToken(address(data.token)).issueTo(manager.ownerOf(tokenId), claimAmount);
        }

        // Refund ineligible balance to issuer
        if (remainingAmount > 0) {
            data.token.safeTransfer(manager.issuer(tokenId), remainingAmount);
        }
    }

    function _afterTermResolved(IAgreementManager manager, uint256 tokenId) internal virtual override {
        delete authTokenBalance[manager][tokenId];

        super._afterTermResolved(manager, tokenId);
    }

    function _claim(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 amount
    ) internal virtual override {
        authTokenBalance[manager][tokenId] = authTokenBalance[manager][tokenId] - amount;
        IAuthorizedShareToken(address(grantData[manager][tokenId].token)).issueTo(manager.ownerOf(tokenId), amount);
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

