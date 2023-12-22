// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./ResolverAbs.sol";
import "./INameResolver.sol";

abstract contract NameResolverAbs is INameResolver, ResolverAbs {
    
    // node's version -> node -> name
    mapping(uint64 => mapping(bytes32 => string)) versionable_names;

    /**
     * Sets the name associated with a MagicDomains node, for reverse records.
     * May only be called by the owner of that node in the MagicDomains registry.
     * @param node The node to update.
     * @param newName The name to to save.
     */
    function setName(bytes32 node, string calldata newName)
        external
        virtual
        authorized(node)
    {
        versionable_names[recordVersions[node]][node] = newName;
        emit NameChanged(node, newName);
    }

    /**
     * Returns the name associated with a MagicDomains node, for reverse records.
     * Defined in EIP181.
     * @param node The MagicDomains node to query.
     * @return The associated name.
     */
    function name(bytes32 node)
        external
        view
        virtual
        override
        returns (string memory)
    {
        return versionable_names[recordVersions[node]][node];
    }

    function supportsInterface(bytes4 interfaceID)
        public
        view
        virtual
        override
        returns (bool)
    {
        return
            interfaceID == type(INameResolver).interfaceId ||
            super.supportsInterface(interfaceID);
    }
}
