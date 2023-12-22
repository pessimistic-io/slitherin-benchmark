// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/**
 * Interface for the new (multicoin) addr function.
 */
interface IAddrResolver {
    event AddrChanged(bytes32 indexed node, address a);

    /**
     * Returns the address associated with a MagicDomain node.
     * @param node The MagicDomain node to query.
     * @return payable The associated address.
     */
    function addr(bytes32 node) external view returns (address payable);
}
