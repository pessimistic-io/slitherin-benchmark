// SPDX-License-Identifier: CC0
pragma solidity >=0.8.13;

import "./HatsOwnedCommon.sol";
import "./Initializable.sol";

/// @notice Single owner authorization mixin using Hats Protocol
/// @dev For inheretence into contracts deployed as proxies. Forked from solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/Owned.sol).
/// @author Hats Protocol
abstract contract HatsOwnedInitializable is HatsOwnedCommon, Initializable {
    /*//////////////////////////////////////////////////////////////
                               INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function _HatsOwned_init(uint256 _ownerHat, address _hatsContract)
        internal
        onlyInitializing
    {
        ownerHat = _ownerHat;
        HATS = IHats(_hatsContract);

        emit OwnerHatUpdated(_ownerHat, _hatsContract);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}

