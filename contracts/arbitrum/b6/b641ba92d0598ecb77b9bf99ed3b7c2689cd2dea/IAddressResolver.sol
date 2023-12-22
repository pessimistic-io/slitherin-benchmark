// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/**
 * Interface for the new (multicoin) addr function.
 */
interface IAddressResolver {
    event AddressChanged(bytes32 indexed node, uint256 coinType, bytes newAddress);

    /**
     * Returns the address associated with a MagicDomain node.
     * @param node The MagicDomain node to query.
     * @param coinType The reference type for the given chain (see EIP-2304)
     * @return binaryAddress The associated address in its native binary format (See EIP-2304's Address Encoding section).
     */
    function addr(bytes32 node, uint256 coinType)
        external
        view
        returns (bytes memory binaryAddress);
}
