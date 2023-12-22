// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

/**
 * @title IPriceOracleConnector
 * @author Souq.Finance
 * @notice Defines the interface of the Price Oracle Connector
 * @notice License: https://souq-peripherals.s3.amazonaws.com/LICENSE.md
 */
interface IPriceOracleConnector {
    /**
     * @dev Emitted when oracle contract is set
     * @param asset The asset address
     * @param oracleContract The oracle contract address
     */
    event OracleContractSet(address indexed asset, address indexed oracleContract);
    /**
     * @dev Emitted when the oracle admin changes
     * @param newOracleAdmin The new oracle admin address
     */
    event NewOracleAdmin(address indexed newOracleAdmin);

    /**
     * @dev Function to get the oracle address of an asset
     * @param asset The asset address
     * @return address the oracle contract
     */
    function getTokenOracleContract(address asset) external view returns (address);

    /**
     * @dev Function to set the oracle address of an asset
     * @param asset The asset address
     * @param oracleContract the oracle contract
     * @param base the bsase string such as USD or ETH
     */
    function setTokenOracleContract(address asset, address oracleContract, string calldata base) external;

    /**
     * @dev Function to get the latest price of an asset
     * @param asset The asset address
     * @return uint256 the latest price
     */
    function getTokenPrice(address asset) external view returns (uint256);
}

