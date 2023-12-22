// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { EnumerableSet } from "./EnumerableSet.sol";

import { IAvoWalletV3 } from "./IAvoWalletV3.sol";
import { IAvoFactory } from "./IAvoFactory.sol";
import { IAvoAuthoritiesList } from "./IAvoAuthoritiesList.sol";

// empty interface used for Natspec docs for nice layout in automatically generated docs:
//
/// @title  AvoAuthoritiesList v3.0.0
/// @notice Tracks allowed authorities for AvoSafes, making available a list of all authorities
/// linked to an AvoSafe or all AvoSafes for a certain authority address.
///
/// If `trackInStorage` flag is set to false, then only an event will be emitted for off-chain tracking.
/// The contract itself will not track avoMultiSafes per signer!
///
/// Upgradeable through AvoAuthoritiesListProxy.
///
/// _@dev Notes:_
/// In off-chain tracking, make sure to check for duplicates (i.e. mapping already exists).
/// This should not happen but when not tracking the data on-chain there is no way to be sure.
interface AvoAuthoritiesList_V3 {

}

abstract contract AvoAuthoritiesListErrors {
    /// @notice thrown when a method is called with invalid params (e.g. zero address)
    error AvoAuthoritiesList__InvalidParams();

    /// @notice thrown when a view method is called that would require storage mapping data,
    /// but the flag `trackInStorage` is set to false and thus data is not available.
    error AvoAuthoritiesList__NotTracked();
}

abstract contract AvoAuthoritiesListConstants is AvoAuthoritiesListErrors {
    /// @notice AvoFactory used to confirm that an address is an Avocado smart wallet
    IAvoFactory public immutable avoFactory;

    /// @notice flag to signal if tracking should happen in storage or only events should be emitted (for off-chain).
    /// This can be set to false to reduce gas cost on expensive chains
    bool public immutable trackInStorage;

    /// @notice constructor sets the immutable `avoFactory` (proxy) address and the `trackInStorage` flag
    constructor(IAvoFactory avoFactory_, bool trackInStorage_) {
        if (address(avoFactory_) == address(0)) {
            revert AvoAuthoritiesList__InvalidParams();
        }
        avoFactory = avoFactory_;

        trackInStorage = trackInStorage_;
    }
}

abstract contract AvoAuthoritiesListVariables is AvoAuthoritiesListConstants {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev add a gap for slot 0 to 100 to easily inherit Initializable / OwnableUpgradeable etc. later on
    uint256[101] private __gap;

    // ---------------- slot 101 -----------------

    /// @notice tracks all AvoSafes mapped to an authority: authority => EnumerableSet AvoSafes list
    /// @dev mappings to a struct with a mapping can not be public because the getter function that Solidity automatically
    /// generates for public variables cannot handle the potentially infinite size caused by mappings within the structs.
    mapping(address => EnumerableSet.AddressSet) internal _safesPerAuthority;

    // ---------------- slot 102 -----------------

    /// @notice tracks all authorities mapped to an AvoSafe: AvoSafe => EnumerableSet authorities list
    mapping(address => EnumerableSet.AddressSet) internal _authoritiesPerSafe;
}

abstract contract AvoAuthoritiesListEvents {
    /// @notice emitted when a new authority <> AvoSafe mapping is added
    event AuthorityMappingAdded(address authority, address avoSafe);

    /// @notice emitted when an authority <> AvoSafe mapping is removed
    event AuthorityMappingRemoved(address authority, address avoSafe);
}

abstract contract AvoAuthoritiesListViews is AvoAuthoritiesListVariables {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice returns true if `authority_` is an allowed authority of `avoSafe_`
    function isAuthorityOf(address avoSafe_, address authority_) public view returns (bool) {
        if (trackInStorage) {
            return _safesPerAuthority[authority_].contains(avoSafe_);
        } else {
            return IAvoWalletV3(avoSafe_).isAuthority(authority_);
        }
    }

    /// @notice returns all authorities for a certain `avoSafe_`.
    /// reverts with `AvoAuthoritiesList__NotTracked()` if `trackInStorage` is set to false (data not available)
    function authorities(address avoSafe_) public view returns (address[] memory) {
        if (trackInStorage) {
            return _authoritiesPerSafe[avoSafe_].values();
        } else {
            revert AvoAuthoritiesList__NotTracked();
        }
    }

    /// @notice returns all avoSafes for a certain `authority_'.
    /// reverts with `AvoAuthoritiesList__NotTracked()` if `trackInStorage` is set to false (data not available)
    function avoSafes(address authority_) public view returns (address[] memory) {
        if (trackInStorage) {
            return _safesPerAuthority[authority_].values();
        } else {
            revert AvoAuthoritiesList__NotTracked();
        }
    }

    /// @notice returns the number of mapped authorities for a certain `avoSafe_'.
    /// reverts with `AvoAuthoritiesList__NotTracked()` if `trackInStorage` is set to false (data not available)
    function authoritiesCount(address avoSafe_) public view returns (uint256) {
        if (trackInStorage) {
            return _authoritiesPerSafe[avoSafe_].length();
        } else {
            revert AvoAuthoritiesList__NotTracked();
        }
    }

    /// @notice returns the number of mapped AvoSafes for a certain `authority_'.
    /// reverts with `AvoAuthoritiesList__NotTracked()` if `trackInStorage` is set to false (data not available)
    function avoSafesCount(address authority_) public view returns (uint256) {
        if (trackInStorage) {
            return _safesPerAuthority[authority_].length();
        } else {
            revert AvoAuthoritiesList__NotTracked();
        }
    }
}

contract AvoAuthoritiesList is
    AvoAuthoritiesListErrors,
    AvoAuthoritiesListConstants,
    AvoAuthoritiesListVariables,
    AvoAuthoritiesListEvents,
    AvoAuthoritiesListViews,
    IAvoAuthoritiesList
{
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice constructor sets the immutable `avoFactory` (proxy) address and the `trackInStorage` flag
    constructor(
        IAvoFactory avoFactory_,
        bool trackInStorage_
    ) AvoAuthoritiesListConstants(avoFactory_, trackInStorage_) {}

    /// @inheritdoc IAvoAuthoritiesList
    function syncAvoAuthorityMappings(address avoSafe_, address[] calldata authorities_) external {
        // make sure `avoSafe_` is an actual AvoSafe
        if (avoFactory.isAvoSafe(avoSafe_) == false) {
            revert AvoAuthoritiesList__InvalidParams();
        }

        uint256 authoritiesLength_ = authorities_.length;

        bool isAuthority_;
        for (uint256 i; i < authoritiesLength_; ) {
            // check if authority is an allowed authority at the AvoWallet
            isAuthority_ = IAvoWalletV3(avoSafe_).isAuthority(authorities_[i]);

            if (isAuthority_) {
                if (trackInStorage) {
                    // `.add()` method also checks if authority is already mapped to the address
                    if (_safesPerAuthority[authorities_[i]].add(avoSafe_) == true) {
                        _authoritiesPerSafe[avoSafe_].add(authorities_[i]);
                        emit AuthorityMappingAdded(authorities_[i], avoSafe_);
                    }
                    // else ignore silently if mapping is already present
                } else {
                    emit AuthorityMappingAdded(authorities_[i], avoSafe_);
                }
            } else {
                if (trackInStorage) {
                    // `.remove()` method also checks if authority is not mapped to the address
                    if (_safesPerAuthority[authorities_[i]].remove(avoSafe_) == true) {
                        _authoritiesPerSafe[avoSafe_].remove(authorities_[i]);
                        emit AuthorityMappingRemoved(authorities_[i], avoSafe_);
                    }
                    // else ignore silently if mapping is not present
                } else {
                    emit AuthorityMappingRemoved(authorities_[i], avoSafe_);
                }
            }

            unchecked {
                ++i;
            }
        }
    }
}

