// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./IRoyaltyManager.sol";
import "./introspection_IERC165.sol";

/**
 * @author ishan@highlight.xyz
 * @dev Abstract contract to be inherited by all valid royalty managers
 */
abstract contract InterfaceSupportRoyaltyManager {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IRoyaltyManager).interfaceId || _supportsERC165Interface(interfaceId);
    }

    /**
     * @dev Used to show support for IERC165, without inheriting contract from IERC165 implementations
     * @param interfaceId Interface ID
     */
    function _supportsERC165Interface(bytes4 interfaceId) internal pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

