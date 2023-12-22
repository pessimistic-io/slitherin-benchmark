// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Term, ITerm} from "./Term.sol";
import {ITokenTransfer, IAgreementManager} from "./ITokenTransfer.sol";
import {IRolesAuthority} from "./IRolesAuthority.sol";
import {Roles} from "./Roles.sol";

import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {IERC165} from "./IERC165.sol";

/// @notice Agreement Term requiring token payment.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/TokenTransfer.sol)
contract TokenTransfer is Term, ITokenTransfer {
    using Roles for IRolesAuthority;
    using SafeERC20 for IERC20;

    /// @dev Storage of TokenTransfer Terms by Agreement ID
    /// Only set at terms creation
    mapping(IAgreementManager => mapping(uint256 => TokenTransferData)) public tokenTransferData;

    /// @dev Storage this contract's token balance per Agreement
    mapping(IAgreementManager => mapping(uint256 => uint256)) public totalPaid;

    IRolesAuthority public whitelistAuthority;

    constructor(IRolesAuthority _whitelistAuthority) {
        whitelistAuthority = _whitelistAuthority;
    }

    function getData(IAgreementManager manager, uint256 tokenId)
        public
        view
        virtual
        override
        returns (TokenTransferData memory)
    {
        return tokenTransferData[manager][tokenId];
    }

    function constraintStatus(IAgreementManager manager, uint256 tokenId)
        public
        view
        virtual
        override(Term, ITerm)
        returns (uint256)
    {
        return percentOfTotal(totalPaid[manager][tokenId], tokenTransferData[manager][tokenId].amount);
    }

    // slither-disable-next-line dead-code
    function _createTerm(
        IAgreementManager manager,
        uint256 tokenId,
        bytes calldata data
    ) internal virtual override {
        TokenTransferData memory _data = abi.decode(data, (TokenTransferData));
        initializeData(manager, tokenId, _data);
    }

    function initializeData(
        IAgreementManager manager,
        uint256 tokenId,
        TokenTransferData memory data
    ) internal {
        whitelistAuthority.checkUserRole(address(data.token), Roles.PAYMENT_TOKEN_ROLE);
        if (data.to == address(0)) revert Term__ZeroAddress();
        if (data.amount == 0) revert Term__ZeroValue();
        if (data.priorTransfers > data.amount) revert TokenTransfer__PriorTransfersTooLarge();

        totalPaid[manager][tokenId] = data.priorTransfers;
        tokenTransferData[manager][tokenId] = data;
    }

    function _settleTerm(IAgreementManager, uint256) internal virtual override {}

    function _cancelTerm(IAgreementManager, uint256) internal virtual override {}

    function _afterTermResolved(IAgreementManager manager, uint256 tokenId) internal virtual override {
        delete totalPaid[manager][tokenId];
        delete tokenTransferData[manager][tokenId];

        super._afterTermResolved(manager, tokenId);
    }

    function payableAmount(IAgreementManager manager, uint256 tokenId) public view virtual override returns (uint256) {
        // Total eligible amount
        uint256 payableUpTo = 0;
        if (tokenTransferData[manager][tokenId].restrictedExercise) {
            payableUpTo = (manager.constraintStatus(tokenId) * tokenTransferData[manager][tokenId].amount) / 100 ether;
        } else {
            payableUpTo = tokenTransferData[manager][tokenId].amount;
        }

        // Adjust for previously paid amount
        return payableUpTo - totalPaid[manager][tokenId];
    }

    function transfer(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 amount
    ) public virtual override {
        if (manager.expired(tokenId)) revert Term__Expired();
        if (amount > payableAmount(manager, tokenId)) revert TokenTransfer__RestrictedExercise();

        totalPaid[manager][tokenId] = totalPaid[manager][tokenId] + amount;

        tokenTransferData[manager][tokenId].token.safeTransferFrom(
            msg.sender,
            tokenTransferData[manager][tokenId].to,
            amount
        );
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, Term) returns (bool) {
        return interfaceId == type(ITokenTransfer).interfaceId || super.supportsInterface(interfaceId);
    }
}

