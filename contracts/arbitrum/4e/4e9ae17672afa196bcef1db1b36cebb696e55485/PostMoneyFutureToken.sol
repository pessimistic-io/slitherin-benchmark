// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Term, IERC165} from "./Term.sol";
import {Right} from "./Right.sol";
import {IFutureToken, ITokenTransfer, IAgreementManager} from "./IFutureToken.sol";

import {ERC165Checker} from "./ERC165Checker.sol";

/// @notice Agreement Term defining rights necessary to claim wrapped tokens to be created in the future.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/PostMoneyFutureToken.sol)
/// @dev Enforced and honored by issuer.
contract PostMoneyFutureToken is Right, IFutureToken {
    /// @dev Storage of Future Equity Terms by Agreement ID
    /// Only set at terms creation
    mapping(IAgreementManager => mapping(uint256 => FutureTokenData)) public futureTokenData;

    function _createTerm(
        IAgreementManager manager,
        uint256 tokenId,
        bytes calldata data
    ) internal virtual override {
        FutureTokenData memory _data = abi.decode(data, (FutureTokenData));

        // Agreement must contain TokenTransfer term
        address tokenTransfer = address(_data.tokenTransfer);
        if (!ERC165Checker.supportsInterface(tokenTransfer, type(ITokenTransfer).interfaceId))
            revert FutureToken__NotTokenTransfer(tokenTransfer);
        if (!manager.containsTerm(tokenId, tokenTransfer)) revert FutureToken__NoTokenTransferTerm();

        if (_data.discount >= 100 ether) revert FutureToken__DiscountTooLarge();
        if (_data.discount == 0 && _data.marketCapitalization == 0) revert FutureToken__IncompleteData();

        futureTokenData[manager][tokenId] = _data;
    }

    function _settleTerm(IAgreementManager, uint256) internal virtual override {
        revert Term__NotIssuer(msg.sender);
    }

    function _cancelTerm(IAgreementManager manager, uint256 tokenId) internal virtual override {
        delete futureTokenData[manager][tokenId];
    }

    /// @inheritdoc IFutureToken
    function effectiveMarketValue(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 marketValue
    ) public view virtual override returns (uint256) {
        // Choose best of marketValue, FutureTokenData.marketCapitalization, or FutureTokenData.discount
        uint256 capValue = marketValue;
        uint256 marketCapValue = futureTokenData[manager][tokenId].marketCapitalization;
        if (marketCapValue != 0 && capValue > marketCapValue) {
            capValue = marketCapValue;
        }
        // Calculate from discount terms
        uint256 discount = futureTokenData[manager][tokenId].discount;
        if (discount > 0) {
            uint256 discounted = (marketValue * (100 ether - discount)) / 100 ether;
            if (capValue > discounted) {
                capValue = discounted;
            }
        }
        return capValue;
    }

    /// @inheritdoc IFutureToken
    function issuableForPricing(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 postMoneyCapitalizationValue,
        uint256 postMoneyTotalSupply
    ) public view virtual override returns (uint256, uint256) {
        // totalIssuable = postMoneySupply * money / postMoneyValue
        // Eligible amount to issue
        uint256 effectiveCap = effectiveMarketValue(manager, tokenId, postMoneyCapitalizationValue);
        uint256 money = ITokenTransfer(futureTokenData[manager][tokenId].tokenTransfer)
            .getData(manager, tokenId)
            .amount;
        return (
            (manager.constraintStatus(tokenId) * postMoneyTotalSupply * money) / effectiveCap / 100 ether,
            effectiveCap
        );
    }

    function validateIssuance(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 postMoneyCapitalizationValue,
        uint256 postMoneyTotalSupply
    ) public view override {
        // Checks that target percentage is between percentage of issuable and issuable + 1
        uint256 effectiveCap = effectiveMarketValue(manager, tokenId, postMoneyCapitalizationValue);
        uint256 money = ITokenTransfer(futureTokenData[manager][tokenId].tokenTransfer)
            .getData(manager, tokenId)
            .amount;
        uint256 targetPercentage = (1 ether * money) / effectiveCap;
        (uint256 issuableShares, ) = issuableForPricing(
            manager,
            tokenId,
            postMoneyCapitalizationValue,
            postMoneyTotalSupply
        );
        uint256 issuablePercentage = (1 ether * issuableShares) / postMoneyTotalSupply;
        uint256 issuablePlusPercentage = (1 ether * (issuableShares + 1)) / postMoneyTotalSupply;
        if (targetPercentage < issuablePercentage || targetPercentage > issuablePlusPercentage)
            revert FutureToken__InvalidIssuance(tokenId, issuableShares, targetPercentage, issuablePercentage);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(Term, IERC165) returns (bool) {
        return interfaceId == type(IFutureToken).interfaceId || super.supportsInterface(interfaceId);
    }
}

