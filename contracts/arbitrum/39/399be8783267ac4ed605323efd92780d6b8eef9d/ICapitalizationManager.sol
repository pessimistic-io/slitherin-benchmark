// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {AuthorizedShareToken, ShareToken} from "./AuthorizedShareToken.sol";

import {IERC165} from "./IERC165.sol";

/// @notice Voting token registry. Future equity agreement tracker. Preferred share rights enforcer.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/ICapitalizationManager.sol)
interface ICapitalizationManager is IERC165 {
    struct PreferredShareTokenData {
        // Token name for new series token
        string name;
        // Token symbol for new series token
        string symbol;
        // Token swap ratio for underlying
        uint256 multiple;
        // Annotation for series sharetoken creation
        string[] shareCreationNotes;
    }

    error CapitalizationManager__ZeroAddress();
    error CapitalizationManager__ZeroValue();
    error CapitalizationManager__IncorrectUnderlying(address token);
    error CapitalizationManager__NotFutureToken(address account);
    error CapitalizationManager__OutstandingObligations();
    error CapitalizationManager__ActiveRound();
    error CapitalizationManager__NoActiveRound();
    error CapitalizationManager__AllowanceFailed();
    error CapitalizationManager__NotFundraisingRoundManager(address account);
    error CapitalizationManager__InvalidFundraisingRoundManager();
    error CapitalizationManager__NotManager(address account);
    error CapitalizationManager__WrongIssuance(uint256 total);
    error CapitalizationManager__AgreementConstrained(uint256 tokenId);
    error CapitalizationManager__InvalidIssuance(
        uint256 issuance,
        uint256 targetPercentage,
        uint256 issuancePercentage
    );

    function authorizedShareToken() external view returns (AuthorizedShareToken);

    function companyShareToken() external view returns (ShareToken);

    function totalSupply() external view returns (uint256);

    function issuableForFunds(uint256 funds) external view returns (uint256);

    function issueForRound(
        address preferredShareToken,
        address account,
        uint256 funds
    ) external returns (uint256);
}

