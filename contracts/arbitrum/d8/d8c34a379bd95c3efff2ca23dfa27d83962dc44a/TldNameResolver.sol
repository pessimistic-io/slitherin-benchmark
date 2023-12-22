// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ITldNameResolver.sol";
import "./ResolverBase.sol";

abstract contract TldNameResolver is ITldNameResolver, ResolverBase {
    mapping (bytes32 => mapping (uint256 => string)) public tldNames;

    /**
    * Sets the tld name associated with an SID node, for reverse records.
    * May only be called by the owner of that node in the SID registry.
    * @param node The node to update.
     */
    function setTldName(bytes32 node, uint256 identifier, string calldata newName) virtual external authorised(node) {
        tldNames[node][identifier] = newName;
        emit TldNameChanged(node, identifier, newName);
    }

    /**
     * Returns the tld name associated with an SID node, for reverse records.
     * @param node The SID node to query.
     * @return The associated name.
     */
    function tldName(bytes32 node, uint256 identifier) virtual override external view returns (string memory) {
        return tldNames[node][identifier];
    }

    function supportsInterface(bytes4 interfaceID) virtual override public pure returns(bool) {
        return interfaceID == type(ITldNameResolver).interfaceId || super.supportsInterface(interfaceID);
    }
}

