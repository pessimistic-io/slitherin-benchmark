// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./ResolverAbs.sol";
import "./IAddressResolver.sol";
import "./IAddrResolver.sol";

abstract contract AddressResolverAbs is
    IAddrResolver,
    IAddressResolver,
    ResolverAbs
{
    // EVM cointypes are calculated by: (0x80000000 | chainId) >>> 0
    // For more info, see https://docs.ens.domains/ens-improvement-proposals/ensip-11-evmchain-address-resolution
    uint256 private constant COIN_TYPE_ETH = 60;
    // Calculated above w/ chainId 42161.
    // All defaults point to Arbitrum Nitro, where MagicDomains are deployed to
    uint256 private constant COIN_TYPE_ARB_NITRO = 2147441487;

    // node's version -> node -> coinType -> address as binary
    mapping(uint64 => mapping(bytes32 => mapping(uint256 => bytes))) versionable_addresses;

    /**
     * Sets the address associated with a MagicDomains node.
     * May only be called by the owner of that node in the MagicDomains registry.
     * @param node The node to update.
     * @param a The address to set.
     */
    function setAddr(bytes32 node, address a)
        external
        virtual
        authorized(node)
    {
        setAddr(node, COIN_TYPE_ARB_NITRO, addressToBytes(a));
    }

    /**
     * Returns the Arbitrum Nitro address associated with a MagicDomains node.
     * @param node The MagicDomains node to query.
     * @return The associated address.
     */
    function addr(bytes32 node)
        public
        view
        virtual
        override
        returns (address payable)
    {
        bytes memory a = addr(node, COIN_TYPE_ARB_NITRO);
        if (a.length == 0) {
            return payable(0);
        }
        return bytesToAddress(a);
    }

    function setAddr(
        bytes32 node,
        uint256 coinType,
        bytes memory a
    ) public virtual authorized(node) {
        emit AddressChanged(node, coinType, a);
        if (coinType == COIN_TYPE_ARB_NITRO) {
            emit AddrChanged(node, bytesToAddress(a));
        }
        versionable_addresses[recordVersions[node]][node][coinType] = a;
    }

    function addr(bytes32 node, uint256 coinType)
        public
        view
        virtual
        override
        returns (bytes memory)
    {
        return versionable_addresses[recordVersions[node]][node][coinType];
    }

    function supportsInterface(bytes4 interfaceID)
        public
        view
        virtual
        override
        returns (bool)
    {
        return
            interfaceID == type(IAddrResolver).interfaceId ||
            interfaceID == type(IAddressResolver).interfaceId ||
            super.supportsInterface(interfaceID);
    }

    function bytesToAddress(bytes memory b)
        internal
        pure
        returns (address payable a)
    {
        require(b.length == 20);
        assembly {
            a := div(mload(add(b, 32)), exp(256, 12))
        }
    }

    function addressToBytes(address a) internal pure returns (bytes memory b) {
        b = new bytes(20);
        assembly {
            mstore(add(b, 32), mul(a, exp(256, 12)))
        }
    }
}
