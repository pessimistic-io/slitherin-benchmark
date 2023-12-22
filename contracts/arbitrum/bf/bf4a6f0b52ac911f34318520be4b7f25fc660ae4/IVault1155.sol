// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {VaultDataTypes} from "./VaultDataTypes.sol";

/**
 * @title IVault1155
 * @author Souq.Finance
 * @notice Interface for Vault1155 contract
 * @notice License: https://souq-etf.s3.amazonaws.com/LICENSE.md
 */

interface IVault1155 {

    function initialize(address _factory, address _feeReceiver) external;

    /**
     * @dev Pauses the contract, preventing certain functions from executing.
     */

    function pause() external;

    /**
     * @dev Unpauses the contract, allowing functions to execute.
     */

    function unpause() external;

    /**
     * @dev Calculates the total quote for a specified number of shares and a fee.
     * @param _numShares The number of shares.
     * @param fee The fee amount.
     * @return An array of total quotes.
     */

    function getTotalQuote(uint256 _numShares, uint256 fee) external returns (uint256[] memory);

    /**
     * @dev Calculates the total quote with a specified VIT address and number of shares.
     * @param _VITAddress The VIT address.
     * @param _numShares The number of shares.
     * @return An array of total quotes.
     */

    function getTotalQuoteWithVIT(address _VITAddress, uint256 _numShares) external returns (uint256[] memory);

    /**
     * @dev Mints Vault tokens for the specified parameters.
     * @param _numShares The number of shares to mint.
     * @param _stableAmount The amount of stable tokens to use for minting.
     * @param _amountPerSwap An array of swap amounts.
     * @param _lockup The lockup period.
     */

    function mintVaultToken(
        uint256 _numShares,
        uint256 _stableAmount,
        uint256[] calldata _amountPerSwap,
        VaultDataTypes.LockupPeriod _lockup
    ) external;

    /**
     * @dev Mints Vault tokens for the specified parameters and a specific VIT address and amount.
     * @param _numShares The number of shares to mint.
     * @param _stableAmount The amount of stable tokens to use for minting.
     * @param _amountPerSwap An array of swap amounts.
     * @param _lockup The lockup period.
     * @param _mintVITAddress The VIT address for minting.
     * @param _mintVITAmount The amount of VIT to mint.
     */

    function mintVaultTokenWithVIT(
        uint256 _numShares,
        uint256 _stableAmount,
        uint256[] calldata _amountPerSwap,
        VaultDataTypes.LockupPeriod _lockup,
        address _mintVITAddress,
        uint256 _mintVITAmount
    ) external;

    /**
     * @dev Sets the reweighter address.
     * @param _reweighter The new reweighter address.
     */

    function setReweighter(address _reweighter) external;

    /**
     * @dev Changes the composition of VITs and their corresponding weights.
     * @param _newVITs An array of new VIT addresses.
     * @param _newAmounts An array of new VIT amounts.
     */

    function changeVITComposition(address[] memory _newVITs, uint256[] memory _newAmounts) external;

    /**
     * @dev Initiates a reweight operation for the specified VITs and amounts.
     * @param _VITs An array of VIT addresses to reweight.
     * @param _amounts An array of corresponding amounts for reweighting.
     */

    function initiateReweight(address[] memory _VITs, uint256[] memory _amounts) external;

    /**
     * @dev Redeems underlying assets for the specified number of shares and tranche.
     * @param _numShares The number of shares to redeem.
     * @param _tranche The tranche to redeem from.
     */

    function redeemUnderlying(uint256 _numShares, uint256 _tranche) external;

    /**
     * @dev Redeems underlying assets for multiple share quantities and tranches.
     * @param _numShares An array of share quantities to redeem.
     * @param _tranche An array of tranches to redeem from.
     */

    function redeemUnderlyingGroup(uint256[] memory _numShares, uint256[] memory _tranche) external;

    /**
     * @dev Retrieves the lockup start time for a specified tranche.
     * @param _tranche The tranche for which to retrieve the lockup start time.
     * @return The lockup start time in Unix timestamp.
     */

    function getLockupStart(uint256 _tranche) external view returns (uint256);

    /**
     * @dev Retrieves the lockup end time for a specified tranche.
     * @param _tranche The tranche for which to retrieve the lockup end time.
     * @return The lockup end time in Unix timestamp.
     */

    function getLockupEnd(uint256 _tranche) external view returns (uint256);

    /**
     * @dev Retrieves the lockup time of a specified tranche.
     * @param _tranche The tranche for which to retrieve the lockup time.
     */

    function getLockupTime(uint256 _tranche) external view returns (uint256);

    /**
     * @dev Retrieves the composition of VITs and their corresponding amounts.
     */

    function getVITComposition() external view returns (address[] memory VITs, uint256[] memory amounts);

    /**
     * @dev Retrieves the total underlying assets across all VITs.
     */

    function getTotalUnderlying() external view returns (uint256[] memory totalUnderlying);

    /**
     * @dev Retrieves the address of the SVS token contract.
     */

    function getSVS() external view returns (address);


    function vaultData() external view returns (VaultDataTypes.VaultData memory);

    /**
     * @dev Retrieves the total underlying assets for a specified tranche.
     * @param tranche The tranche for which to retrieve the total underlying assets.
     */

    function getTotalUnderlyingByTranche(uint256 tranche) external view returns (uint256[] memory);
}

