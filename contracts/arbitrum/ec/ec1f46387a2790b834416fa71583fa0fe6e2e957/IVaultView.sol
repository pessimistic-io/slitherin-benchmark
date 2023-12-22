// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./VaultStorage.sol";

/**
 * @title Knox Vault View Interface
 */

interface IVaultView {
    /************************************************
     *  VIEW
     ***********************************************/

    /**
     * @notice returns the address of assigned actors
     * @return address of owner
     * @return address of fee recipient
     * @return address of keeper
     */
    function getActors()
        external
        view
        returns (
            address,
            address,
            address
        );

    /**
     * @notice returns the auction window offsets
     * @return start offset
     * @return end offset
     */
    function getAuctionWindowOffsets() external view returns (uint256, uint256);

    /**
     * @notice returns the address of connected services
     * @return address of Auction
     * @return address of Premia Pool
     * @return address of Pricer
     * @return address of Queue
     */
    function getConnections()
        external
        view
        returns (
            address,
            address,
            address,
            address
        );

    /**
     * @notice returns option delta
     * @return option delta as a 64x64 fixed point number
     */
    function getDelta64x64() external view returns (int128);

    /**
     * @notice returns the current epoch
     * @return current epoch id
     */
    function getEpoch() external view returns (uint64);

    /**
     * @notice returns the option by epoch id
     * @return option parameters
     */
    function getOption(uint64 epoch)
        external
        view
        returns (VaultStorage.Option memory);

    /**
     * @notice returns option type (call/put)
     * @return true if opton is a call
     */
    function getOptionType() external view returns (bool);

    /**
     * @notice returns performance fee
     * @return performance fee as a 64x64 fixed point number
     */
    function getPerformanceFee64x64() external view returns (int128);

    /**
     * @notice returns the total amount of collateral and short contracts to distribute
     * @param assetAmount quantity of assets to withdraw
     * @return distribution amount in collateral asset
     * @return distribution amount in the short contracts
     */
    function previewDistributions(uint256 assetAmount)
        external
        view
        returns (uint256, uint256);

    /**
     * @notice estimates the total reserved "active" collateral
     * @dev collateral is reserved from the auction to ensure the Vault has sufficent funds to
     * cover the APY fee
     * @return estimated amount of reserved "active" collateral
     */
    function previewReserves() external view returns (uint256);

    /**
     * @notice estimates the total number of contracts from the collateral and reserves held by the vault
     * @param strike64x64 strike price of the option as 64x64 fixed point number
     * @param collateral amount of collateral held by vault
     * @param reserves amount of reserves held by vault
     * @return estimated number of contracts
     */
    function previewTotalContracts(
        int128 strike64x64,
        uint256 collateral,
        uint256 reserves
    ) external view returns (uint256);

    /**
     * @notice calculates the total active vault by deducting the premiums from the ERC20 balance
     * @return total active collateral
     */
    function totalCollateral() external view returns (uint256);

    /**
     * @notice calculates the short position value denominated in the collateral asset
     * @return total short position in collateral amount
     */
    function totalShortAsCollateral() external view returns (uint256);

    /**
     * @notice returns the amount in short contracts underwitten by the vault
     * @return total short contracts
     */
    function totalShortAsContracts() external view returns (uint256);
}

