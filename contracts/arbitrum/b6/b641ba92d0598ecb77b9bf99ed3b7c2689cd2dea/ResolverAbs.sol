// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {ERC165Upgradeable} from "./ERC165Upgradeable.sol";
import {IVersionableResolver} from "./IVersionableResolver.sol";

abstract contract ResolverAbs is ERC165Upgradeable, IVersionableResolver {
    
    // node -> node version
    mapping(bytes32 => uint64) public recordVersions;

    function isAuthorized(bytes32 node) internal view virtual returns (bool);

    modifier authorized(bytes32 node) {
        require(isAuthorized(node), "ResolverAbs: not authorized");
        _;
    }

    /**
     * Increments the record version associated with a MagicDomains node.
     * May only be called by the owner of that node in the MagicDomains registry.
     * @param node The node to update.
     */
    function clearRecords(bytes32 node) public virtual authorized(node) {
        recordVersions[node]++;
        emit VersionChanged(node, recordVersions[node]);
    }

    function supportsInterface(bytes4 interfaceID)
        public
        view
        virtual
        override
        returns (bool)
    {
        return
            interfaceID == type(IVersionableResolver).interfaceId ||
            super.supportsInterface(interfaceID);
    }
}
