// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {IAgreementManager} from "./IAgreementManager.sol";

import {IERC165} from "./IERC165.sol";

/// @notice Base implementation for composable agreements.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/ITerm.sol)
interface ITerm is IERC165 {
    error Term__NotManager(address account);
    error Term__TermNotSatisfied();
    error Term__ZeroValue();
    error Term__ZeroAddress();
    error Term__NotIssuer(address account);
    error Term__Expired();
    error Term__NotTokenOwner(address account);

    /**
     * @notice Percent complete value according to satisfaction of terms
     * @dev Computed with standard ether decimals
     */
    function constraintStatus(IAgreementManager manager, uint256 tokenId) external view returns (uint256);

    /**
     * @notice Create new term
     * @dev Only callable by manager
     * @param manager AgreementManager contract address
     * @param tokenId Agreement Token ID Created in Agreement Manager
     * @param data Initialization data struct
     */
    function createTerm(
        IAgreementManager manager,
        uint256 tokenId,
        bytes calldata data
    ) external;

    /**
     * @notice Final resolution of terms
     * @dev Only callable by manager
     * This resolves the term in the agreement owner's favor whenever possible
     */
    function settleTerm(IAgreementManager manager, uint256 tokenId) external;

    /**
     * @notice Reversion of any unsettled terms
     * @dev Only callable by manager
     * This resolves the term in the agreement issuer's favor whenever possible
     */
    function cancelTerm(IAgreementManager manager, uint256 tokenId) external;
}

