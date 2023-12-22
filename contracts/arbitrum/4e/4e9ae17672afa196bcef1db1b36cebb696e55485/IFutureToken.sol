// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ITokenTransfer} from "./ITokenTransfer.sol";
import {ITerm, IAgreementManager} from "./ITerm.sol";

/// @notice Agreement Term defining rights necessary to claim wrapped tokens to be created in the future.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/IFutureToken.sol)
/// @dev Enforced and honored by issuer.
interface IFutureToken is ITerm {
    /// @dev Data structure for FutureToken properties
    struct FutureTokenData {
        // The minimum discount applied to determine required amount with ether decimals
        uint256 discount;
        // A set market cap to determine best discount
        uint256 marketCapitalization;
        // The term contract to retrieve the value contributed by the investor
        ITokenTransfer tokenTransfer;
    }

    error FutureToken__DiscountTooLarge();
    error FutureToken__IncompleteData();
    error FutureToken__NotTokenTransfer(address term);
    error FutureToken__NoTokenTransferTerm();
    error FutureToken__InvalidIssuance(
        uint256 tokenId,
        uint256 issuance,
        uint256 targetPercentage,
        uint256 issuancePercentage
    );

    /**
     * @notice Computes effective token valuation for term
     * @param tokenId Agreement ID Created in Agreement Manager
     * @param marketValue Token market cap value
     */
    function effectiveMarketValue(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 marketValue
    ) external view returns (uint256);

    /**
     * @notice Amount of token eligible for issuance
     * @dev Also returns effective market cap value
     */
    function issuableForPricing(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 capitalizationValue,
        uint256 totalSupply
    ) external view returns (uint256, uint256);

    function validateIssuance(
        IAgreementManager manager,
        uint256 tokenId,
        uint256 postMoneyCapitalizationValue,
        uint256 postMoneyTotalSupply
    ) external view;
}

