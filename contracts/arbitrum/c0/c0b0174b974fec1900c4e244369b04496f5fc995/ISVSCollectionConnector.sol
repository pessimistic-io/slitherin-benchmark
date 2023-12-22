// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {ICollectionConnector} from "./ICollectionConnector.sol";

/**
 * @title ISVSCollectionConnector
 * @author Souq.Finance
 * @notice Defines the interface of the SVS collection connectors inheriting the ICollectionConnector
 * @notice License: https://souq-peripherals.s3.amazonaws.com/LICENSE.md
 */

interface ISVSCollectionConnector is ICollectionConnector {
    /**
     * @dev Returns the VIT and composition of the VAULT specified
     * @param collection The address of the collection
     */
    function getVITs(address collection) external view returns (address[] memory VITs, uint256[] memory amounts);

    /**
     * @dev Function that gets the lockup times array from the vault data
     * @param collection The address of the collection
     * @return lockupTimes The lockup times array
     */
    function getLockupTimes(address collection) external view returns (uint256[] memory lockupTimes);

    /**
     * @dev Function that gets the lockup time of a specific token id (tranche)
     * @param collection The address of the collection
     * @param tokenId The Vault tranche id
     * @return uint256 The lockup time
     */
    function getLockupTime(address collection, uint256 tokenId) external view returns (uint256);
}

