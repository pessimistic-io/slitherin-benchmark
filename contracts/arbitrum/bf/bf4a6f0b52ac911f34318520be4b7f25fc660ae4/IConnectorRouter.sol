// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {DataTypes} from "./DataTypes.sol";

/**
 * @title IConnectorRouter
 * @author Souq.Finance
 * @notice Defines the interface of the connector router
 * @notice License: https://souq-peripherals.s3.amazonaws.com/LICENSE.md
 */
interface IConnectorRouter {
    event YieldDistributorSet(address indexed vaultAddress, address indexed yieldDistributorAddress);
    event YieldDistributorDeleted(address indexed vaultAddress);

    event StakingContractSet(address indexed tokenAddress, address indexed stakingContractAddress);
    event StakingContractDeleted(address indexed stakingContractAddress);

    event SwapContractSet(address indexed tokenAddress, address indexed swapContractAddress);
    event SwapContractDeleted(address indexed swapContractAddress);

    event OracleConnectorSet(address indexed tokenAddress, address indexed oracleConnectorAddress);
    event OracleConnectorDeleted(address indexed oracleConnectorAddress);

    event CollectionConnectorSet(address indexed collection, address indexed collectionConnectorAddress);
    event CollectionConnectorDeleted(address indexed collectionConnectorAddress);

    event StablecoinYieldConnectorSet(address indexed tokenAddress, address indexed stablecoinYieldConnectorAddress);
    event StablecoinYieldConnectorDeleted(address indexed stablecoinYieldConnectorAddress);

    /**
     * @dev Sets the initial owner and timelock address of the contract.
     * @param timelock address
     */
    function initialize(address timelock) external;

    /**
     * @dev Returns the address of the yield distributor contract for a given vault.
     * @param vaultAddress address
     * @return address of the yield distributor contract
     */
    function getYieldDistributor(address vaultAddress) external view returns (address);

    function setYieldDistributor(address vaultAddress, address yieldDistributorAddress) external;

    function deleteYieldDistributor(address vaultAddress) external;

    function getStakingContract(address tokenAddress) external view returns (address);

    function setStakingContract(address tokenAddress, address stakingContractAddress) external;

    function deleteStakingContract(address tokenAddress) external;

    function getSwapContract(address tokenAddress) external view returns (address);

    function setSwapContract(address tokenIn, address tokenOut, address swapContractAddress) external;

    function deleteSwapContract(address tokenAddress) external;

    function getOracleConnectorContract(address tokenAddress) external view returns (address);

    function setOracleConnectorContract(address tokenAddress, address oracleConnectorAddress) external;

    function deleteOracleConnectorContract(address tokenAddress) external;

    function getCollectionConnectorContract(address collection) external view returns (address);

    function setCollectionConnectorContract(address collection, address collectionConnectorAddress) external;

    function deleteCollectionConnectorContract(address collection) external;

    function getStablecoinYieldConnectorContract(address tokenAddress) external view returns (address);

    function setStablecoinYieldConnectorContract(address tokenAddress, address stablecoinYieldConnectorAddress) external;

    function deleteStablecoinYieldConnectorContract(address tokenAddress) external;
}

