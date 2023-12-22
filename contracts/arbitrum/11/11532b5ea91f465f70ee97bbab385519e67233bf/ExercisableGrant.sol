// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ITerm, IAgreementManager} from "./Term.sol";
import {Grant} from "./Grant.sol";
import {DelegatingGrant, GrantLock} from "./DelegatingGrant.sol";
import {AuthorizedShareGrant} from "./AuthorizedShareGrant.sol";
import {IAuthorizedShareToken, ShareToken} from "./IAuthorizedShareToken.sol";
import {ITokenTransfer} from "./ITokenTransfer.sol";

import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {ERC165Checker} from "./ERC165Checker.sol";

/// @notice Agreement Term grant that issues shares to vault.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/ExercisableGrant.sol)
/// @dev This grant implements a two step redemption process, issue => claim
contract ExercisableGrant is DelegatingGrant, AuthorizedShareGrant {
    using SafeERC20 for IERC20;

    error ExercisableGrant__MissingTerm();
    error ExercisableGrant__NotTokenTransfer();
    error ExercisableGrant__InsufficientIssuable();

    mapping(IAgreementManager => mapping(uint256 => ITokenTransfer)) public tokenTransfer;

    function _createTerm(
        IAgreementManager manager,
        uint256 tokenId,
        bytes calldata data
    ) internal virtual override {
        (GrantData memory data_, ITokenTransfer _tokenTransfer) = abi.decode(data, (GrantData, ITokenTransfer));
        checkTokenInterface(address(data_.token));
        if (data_.amount == 0) revert Term__ZeroValue();
        if (!ERC165Checker.supportsInterface(address(_tokenTransfer), type(ITokenTransfer).interfaceId))
            revert ExercisableGrant__NotTokenTransfer();
        if (!manager.containsTerm(tokenId, address(_tokenTransfer))) revert ExercisableGrant__MissingTerm();

        grantData[manager][tokenId] = data_;
        tokenBalance[manager][tokenId] = data_.amount;
        authTokenBalance[manager][tokenId] = data_.amount;
        tokenTransfer[manager][tokenId] = _tokenTransfer;

        deployGrantLock(manager, tokenId, IAuthorizedShareToken(address(data_.token)).underlying());

        // transfer amount
        data_.token.safeTransferFrom(manager.issuer(tokenId), address(this), data_.amount);
    }

    function _settleTerm(IAgreementManager manager, uint256 tokenId) internal virtual override {
        GrantData memory data = grantData[manager][tokenId];
        ShareToken shareToken = IAuthorizedShareToken(address(data.token)).underlying();
        GrantLock grantLockAddress = grantLock[manager][tokenId];
        uint256 authBalance = authTokenBalance[manager][tokenId];

        // Settle remaining lock balance to token owner
        address agreementOwner = manager.ownerOf(tokenId);
        uint256 lockBalance = shareToken.balanceOf(address(grantLockAddress));
        if (lockBalance > 0) {
            grantLockAddress.withdraw(agreementOwner, lockBalance);
        }

        // Settle remaining auth balance to token owner
        if (authBalance > 0) {
            IAuthorizedShareToken(address(data.token)).issueTo(agreementOwner, authBalance);
        }
    }

    function _cancelTerm(IAgreementManager manager, uint256 tokenId) internal virtual override {
        // Settle eligible balance to token owner
        // This prevents scams where an issuer receives payment, then cancels the agreement
        // More lenient (for the issuer) clawback provisions can be added as additional Terms
        GrantData memory data = grantData[manager][tokenId];
        ShareToken shareToken = IAuthorizedShareToken(address(data.token)).underlying();
        uint256 claimAmount = claimable(manager, tokenId);
        uint256 authBalance = authTokenBalance[manager][tokenId];
        GrantLock grantLockAddress = grantLock[manager][tokenId];
        ITokenTransfer.TokenTransferData memory tokenTransferData = tokenTransfer[manager][tokenId].getData(
            manager,
            tokenId
        );

        address agreementOwner = manager.ownerOf(tokenId);
        address agreementIssuer = manager.issuer(tokenId);
        uint256 lockBalance = shareToken.balanceOf(address(grantLockAddress));
        uint256 claimFromLock = lockBalance >= claimAmount ? claimAmount : lockBalance;
        uint256 lockRemainder = lockBalance - claimFromLock;
        uint256 authClaimAmount = claimAmount - claimFromLock;
        uint256 authRemainder = authBalance - authClaimAmount;

        // Claw back ineligible shares to issuer
        if (lockRemainder > 0) {
            // Issuer pay for exercised shares
            tokenTransferData.token.safeTransferFrom(
                agreementIssuer,
                agreementOwner,
                (lockRemainder * tokenTransferData.amount) / data.amount
            );
            // Transfer shares
            grantLockAddress.withdraw(agreementIssuer, lockRemainder);
        }

        // Grant eligible issued shares
        if (claimFromLock > 0) {
            grantLockAddress.withdraw(agreementOwner, claimAmount);
        }

        // If more claims needed, take from authorized shares and issue
        if (authClaimAmount > 0) {
            IAuthorizedShareToken(address(data.token)).issueTo(agreementOwner, authClaimAmount);
        }

        // Refund ineligible authorized shares to issuer
        if (authRemainder > 0) {
            data.token.safeTransfer(agreementIssuer, authRemainder);
        }
    }

    function _afterTermResolved(IAgreementManager manager, uint256 tokenId) internal virtual override {
        delete authTokenBalance[manager][tokenId];
        delete tokenTransfer[manager][tokenId];

        super._afterTermResolved(manager, tokenId);
    }

    function issue(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 amount
    ) public virtual {
        if (manager.expired(tokenId)) revert Term__Expired();
        if (msg.sender != manager.ownerOf(tokenId)) revert Term__NotTokenOwner(msg.sender);
        if (amount > issuable(manager, tokenId)) revert ExercisableGrant__InsufficientIssuable();

        authTokenBalance[manager][tokenId] = authTokenBalance[manager][tokenId] - amount;
        IAuthorizedShareToken(address(grantData[manager][tokenId].token)).issueTo(
            address(grantLock[manager][tokenId]),
            amount
        );
    }

    function issuable(IAgreementManager manager, uint256 tokenId) public view virtual returns (uint256) {
        // Total eligible amount
        uint256 grantAmount = grantData[manager][tokenId].amount;
        uint256 claimableUpTo = (tokenTransfer[manager][tokenId].constraintStatus(manager, tokenId) * grantAmount) /
            100 ether;
        // Adjust for previously issued amount
        return claimableUpTo - (grantAmount - authTokenBalance[manager][tokenId]);
    }

    function issueAndClaim(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 amount
    ) public virtual {
        if (manager.expired(tokenId)) revert Term__Expired();
        address tokenOwner = manager.ownerOf(tokenId);
        if (msg.sender != tokenOwner) revert Term__NotTokenOwner(msg.sender);
        if (amount > claimable(manager, tokenId)) revert Grant__InsufficientClaimable();

        tokenBalance[manager][tokenId] = tokenBalance[manager][tokenId] - amount;
        authTokenBalance[manager][tokenId] = authTokenBalance[manager][tokenId] - amount;
        IAuthorizedShareToken(address(grantData[manager][tokenId].token)).issueTo(tokenOwner, amount);
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

