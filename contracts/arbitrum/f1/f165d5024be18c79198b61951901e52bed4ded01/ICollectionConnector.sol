// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

/**
 * @title ICollectionConnector
 * @author Souq.Finance
 * @notice Defines the interface of the Collection Connector
 * @notice License: https://souq-peripherals.s3.amazonaws.com/LICENSE.md
 */

interface ICollectionConnector {
    /**
     * @dev Initialize the connector with the address of the addresses registry
     * @param _addressesRegistry The addresses registry contract
     */
    function initialize(address _addressesRegistry) external;

    /**
     * @dev External function to get the attribute by token id stored locally.
     * @param collection The collection contract address
     * @param _id The token id to get the identifier of
     * @return uint256 the attribute for the token id in the specified collection (can be the rarity or maturity/start of a financial token in other contract versions)
     */
    function getAttributeLocal(address collection, uint256 _id) external view returns (uint256);

    /**
     * @dev External function to get the attribute by id.
     * @param collection The collection contract address
     * @param _id The token id to get the identifier of
     * @return uint256 the attribute for the token id in the specified collection (can be the rarity or maturity/start of a financial token in other contract versions)
     */
    function getAttribute(address collection, uint256 _id) external view returns (uint256);

    /**
     * @dev External function to set the attribute of a token id of a collection address locally
     * @param collection The collection contract address
     * @param _id The id of the token
     * @param _attribute The attribute of that token id
     */
    function setAttribute(address collection, uint256 _id, uint256 _attribute) external;

    /**
     * @dev External function to batch set the rarities of multiple token ids of a collection address
     * @param collection The collection contract address
     * @param _ids The array of token ids
     * @param _attributes The array of rarities to set
     */
    function setAttributeBatch(address collection, uint256[] calldata _ids, uint256[] calldata _attributes) external;

    /**
     * @dev External function to check if the balance of a given id owned by an address
     * @param collection The collection contract address
     * @param _id The id of the token
     * @param _account The address of the tokens owner
     * @return uint256 The balance of a specific token id
     */
    function getBalance(address collection, uint256 _id, address _account) external view returns (uint256);

    /**
     * @dev External function to check if all tokens are approved for the sending contract (like the factory)
     * @param collection The collection contract address
     * @param _account The address of the tokens owner
     * @return bool True If approved All
     */
    function getApproved(address collection, address _account) external view returns (bool);

    /**
     * @dev External function to transfer token id of specific amount from the owner to the requesting address
     * @param collection The collection contract address
     * @param _account The address of the tokens owner
     * @param _id The token id to be transferred
     * @param _amount The amount to be transferred
     */
    function transfer(address collection, address _account, uint256 _id, uint256 _amount) external;

    /**
     * @dev External function to batch transfer tokens from the owner to the requesting address
     * @param collection The collection contract address
     * @param _account The address of the tokens owner
     * @param _ids Array of token ids
     * @param _amounts Array of amounts. Array length should match the token ids array length.
     */
    function transferBatch(address collection, address _account, uint256[] calldata _ids, uint256[] calldata _amounts) external;
}

