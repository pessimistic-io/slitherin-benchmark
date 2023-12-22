// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ILoot8UniformCollection {

    /**
     * @dev Returns a contract-level metadata URI.
     */
    function contractURI() external view returns (string memory);

    /**
     * @dev Updates the metadata URI for the collection
     * @param _contractURI string new contract URI
     */
    function updateContractURI(string memory _contractURI) external;

}
