// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {AnnotatingMulticall} from "./AnnotatingMulticall.sol";
import {AuthorizedShareToken} from "./AuthorizedShareToken.sol";
import {IAgreementManager} from "./IAgreementManager.sol";
import {IGrant} from "./IGrant.sol";
import {IAuthorizedShareGrant} from "./IAuthorizedShareGrant.sol";
import {StockPlanFactory} from "./StockPlanFactory.sol";
import {Auth, Authority} from "./Auth.sol";

import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {ERC165Checker} from "./ERC165Checker.sol";

/// @notice A stock plan with model agreements.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/StockPlan.sol)
contract StockPlan is Auth, AnnotatingMulticall {
    using SafeERC20 for IERC20;

    error StockPlan__NotAuthorizedShareGrant(address firstTerm);
    error StockPlan__TimeInPast();
    error StockPlan__NoModelAgreement();
    error StockPlan__ModelAgreementEmpty();
    error StockPlan__NotModelAgreement();
    error StockPlan__PlanExpired();
    error StockPlan__AllowanceFailed();
    error StockPlan__WrongCompanyToken(address token);

    event PlanAmended(uint256 newExpiration, address[][] newTerms);

    /**
     * Variables
     */

    AuthorizedShareToken public immutable authorizedShareToken;

    /// @notice Agreement Manager contract address.
    IAgreementManager public immutable agreementManager;

    // Stock plan data
    uint256 public expiration;

    address[][] private modelAgreementTerms;

    /// @notice Create a new Stock Plan
    /// @dev Retrieves initialization data from StockPlanFactory contract
    constructor() Auth(StockPlanFactory(msg.sender).planOwner(), StockPlanFactory(msg.sender).planAuthority()) {
        // Retrieve the data from the factory contract.
        uint256 _expiration = StockPlanFactory(msg.sender).planExpiration();
        address[][] memory _modelAgreementTerms = StockPlanFactory(msg.sender).getPlanModelAgreementTerms();

        // Validate and store deployment data.
        if (_expiration <= block.timestamp) revert StockPlan__TimeInPast();
        _verifyAgreementTerms(_modelAgreementTerms);
        expiration = _expiration;
        modelAgreementTerms = _modelAgreementTerms;

        authorizedShareToken = StockPlanFactory(msg.sender).planAuthorizedShareToken();
        agreementManager = StockPlanFactory(msg.sender).planAgreementManager();
    }

    function _verifyAgreementTerms(address[][] memory terms) private view {
        if (terms.length == 0) revert StockPlan__NoModelAgreement();
        for (uint256 i = 0; i < terms.length; i++) {
            if (terms[i].length == 0) revert StockPlan__ModelAgreementEmpty();
            address firstTerm = terms[i][0];
            if (
                !ERC165Checker.supportsInterface(firstTerm, type(IGrant).interfaceId) ||
                !ERC165Checker.supportsInterface(firstTerm, type(IAuthorizedShareGrant).interfaceId)
            ) revert StockPlan__NotAuthorizedShareGrant(firstTerm);
        }
    }

    function getModelAgreementTerms() external view returns (address[][] memory) {
        return modelAgreementTerms;
    }

    /// @dev Intended role: Board.
    function withdraw(IERC20 token, uint256 amount) external requiresAuth {
        token.safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Grant equity from stock plan
     * @dev First term must be Grant.  Intended role: Board.
     */
    function issueGrantFromPlan(uint256 modelIndex, IAgreementManager.AgreementTerms calldata terms)
        external
        requiresAuth
        returns (uint256)
    {
        if (block.timestamp > expiration) revert StockPlan__PlanExpired();
        address[] memory agreementTerms = modelAgreementTerms[modelIndex];
        if (terms.terms.length != agreementTerms.length) revert StockPlan__NotModelAgreement();
        for (uint256 i = 0; i < terms.terms.length; i++) {
            if (terms.terms[i] != agreementTerms[i]) revert StockPlan__NotModelAgreement();
        }
        IGrant.GrantData memory grantData = abi.decode(terms.termsData[0], (IGrant.GrantData));
        address grantToken = address(grantData.token);
        if (grantToken != address(authorizedShareToken)) revert StockPlan__WrongCompanyToken(grantToken);

        if (!authorizedShareToken.increaseAllowance(agreementTerms[0], grantData.amount))
            revert StockPlan__AllowanceFailed();

        // handle plan specific accounting
        return agreementManager.createAgreement(terms);
    }

    /// @dev Intended role: Board.
    function cancelAgreement(uint256 tokenId) external requiresAuth {
        agreementManager.cancelAgreement(tokenId);
    }

    function amendPlan(uint256 newExpiration, address[][] memory newModelAgreementTerms) external requiresAuth {
        if (newExpiration <= block.timestamp) revert StockPlan__TimeInPast();
        _verifyAgreementTerms(newModelAgreementTerms);
        emit PlanAmended(newExpiration, newModelAgreementTerms);

        expiration = newExpiration;
        modelAgreementTerms = newModelAgreementTerms;
    }
}

