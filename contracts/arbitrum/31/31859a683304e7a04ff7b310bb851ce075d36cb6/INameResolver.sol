// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

interface INameResolver {
    event NameChanged(bytes32 indexed node, string name);

    /**
     * Returns the name associated with an ENS node, for reverse records.
     * Defined in EIP181.
     * @param node The ENS node to query.
     * @return name The associated name.
     */
    function name(bytes32 node) external view returns (string memory name);

    /**
     * Sets the name associated with a MagicDomains node, for reverse records.
     * May only be called by the owner of that node in the MagicDomains registry.
     * @param node The node to update.
     * @param newName The name to to save.
     */
    function setName(bytes32 node, string calldata newName) external;
}
