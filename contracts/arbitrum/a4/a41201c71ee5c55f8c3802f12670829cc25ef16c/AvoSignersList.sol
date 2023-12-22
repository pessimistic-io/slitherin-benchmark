// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { EnumerableSet } from "./EnumerableSet.sol";
import { Address } from "./Address.sol";

import { IAvoMultisigV3 } from "./IAvoMultisigV3.sol";
import { IAvoFactory } from "./IAvoFactory.sol";
import { IAvoSignersList } from "./IAvoSignersList.sol";

// empty interface used for Natspec docs for nice layout in automatically generated docs:
//
/// @title  AvoSignersList v3.0.0
/// @notice Tracks allowed signers for AvoMultiSafes, making available a list of all signers
/// linked to an AvoMultiSafe or all AvoMultiSafes for a certain signer address.
///
/// If `trackInStorage` flag is set to false, then only an event will be emitted for off-chain tracking.
/// The contract itself will not track avoMultiSafes per signer!
///
/// Upgradeable through AvoSignersListProxy
///
/// _@dev Notes:_
/// In off-chain tracking, make sure to check for duplicates (i.e. mapping already exists).
/// This should not happen but when not tracking the data on-chain there is no way to be sure.
interface AvoSignersList_V3 {

}

abstract contract AvoSignersListErrors {
    /// @notice thrown when a method is called with invalid params (e.g. zero address)
    error AvoSignersList__InvalidParams();

    /// @notice thrown when a view method is called that would require storage mapping data,
    /// but the flag `trackInStorage` is set to false and thus data is not available.
    error AvoSignersList__NotTracked();
}

abstract contract AvoSignersListConstants is AvoSignersListErrors {
    /// @notice AvoFactory used to confirm that an address is an Avocado smart wallet
    IAvoFactory public immutable avoFactory;

    /// @notice flag to signal if tracking should happen in storage or only events should be emitted (for off-chain).
    /// This can be set to false to reduce gas cost on expensive chains
    bool public immutable trackInStorage;

    /// @notice constructor sets the immutable `avoFactory` (proxy) address and the `trackInStorage` flag
    constructor(IAvoFactory avoFactory_, bool trackInStorage_) {
        if (address(avoFactory_) == address(0)) {
            revert AvoSignersList__InvalidParams();
        }
        avoFactory = avoFactory_;

        trackInStorage = trackInStorage_;
    }
}

abstract contract AvoSignersListVariables is AvoSignersListConstants {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev add a gap for slot 0 to 100 to easily inherit Initializable / OwnableUpgradeable etc. later on
    uint256[101] private __gap;

    // ---------------- slot 101 -----------------

    /// @notice tracks all AvoMultiSafes mapped to a signer: signer => EnumerableSet AvoMultiSafes list
    /// @dev mappings to a struct with a mapping can not be public because the getter function that Solidity automatically
    /// generates for public variables cannot handle the potentially infinite size caused by mappings within the structs.
    mapping(address => EnumerableSet.AddressSet) internal _safesPerSigner;
}

abstract contract AvoSignersListEvents {
    /// @notice emitted when a new signer <> AvoMultiSafe mapping is added
    event SignerMappingAdded(address signer, address avoMultiSafe);

    /// @notice emitted when a signer <> AvoMultiSafe mapping is removed
    event SignerMappingRemoved(address signer, address avoMultiSafe);
}

abstract contract AvoSignersListViews is AvoSignersListVariables {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice returns true if `signer_` is an allowed signer of `avoMultiSafe_`
    function isSignerOf(address avoMultiSafe_, address signer_) public view returns (bool) {
        if (trackInStorage) {
            return _safesPerSigner[signer_].contains(avoMultiSafe_);
        } else {
            return IAvoMultisigV3(avoMultiSafe_).isSigner(signer_);
        }
    }

    /// @notice returns all signers for a certain `avoMultiSafe_`
    function signers(address avoMultiSafe_) public view returns (address[] memory) {
        if (Address.isContract(avoMultiSafe_)) {
            return IAvoMultisigV3(avoMultiSafe_).signers();
        } else {
            return new address[](0);
        }
    }

    /// @notice returns all AvoMultiSafes for a certain `signer_'.
    /// reverts with `AvoSignersList__NotTracked()` if `trackInStorage` is set to false (data not available)
    function avoMultiSafes(address signer_) public view returns (address[] memory) {
        if (trackInStorage) {
            return _safesPerSigner[signer_].values();
        } else {
            revert AvoSignersList__NotTracked();
        }
    }

    /// @notice returns the number of mapped signers for a certain `avoMultiSafe_'
    function signersCount(address avoMultiSafe_) public view returns (uint256) {
        if (Address.isContract(avoMultiSafe_)) {
            return IAvoMultisigV3(avoMultiSafe_).signersCount();
        } else {
            return 0;
        }
    }

    /// @notice returns the number of mapped avoMultiSafes for a certain `signer_'
    /// reverts with `AvoSignersList__NotTracked()` if `trackInStorage` is set to false (data not available)
    function avoMultiSafesCount(address signer_) public view returns (uint256) {
        if (trackInStorage) {
            return _safesPerSigner[signer_].length();
        } else {
            revert AvoSignersList__NotTracked();
        }
    }
}

contract AvoSignersList is
    AvoSignersListErrors,
    AvoSignersListConstants,
    AvoSignersListVariables,
    AvoSignersListEvents,
    AvoSignersListViews,
    IAvoSignersList
{
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice constructor sets the immutable `avoFactory` (proxy) address and the `trackInStorage` flag
    constructor(IAvoFactory avoFactory_, bool trackInStorage_) AvoSignersListConstants(avoFactory_, trackInStorage_) {}

    /// @inheritdoc IAvoSignersList
    function syncAddAvoSignerMappings(address avoMultiSafe_, address[] calldata addSigners_) external {
        // make sure avoMultiSafe_ is an actual AvoMultiSafe
        if (avoFactory.isAvoSafe(avoMultiSafe_) == false) {
            revert AvoSignersList__InvalidParams();
        }

        uint256 addSignersLength_ = addSigners_.length;
        if (addSignersLength_ == 1) {
            // if adding just one signer, using `isSigner()` is cheaper than looping through allowed signers here
            if (IAvoMultisigV3(avoMultiSafe_).isSigner(addSigners_[0])) {
                if (trackInStorage) {
                    // `.add()` method also checks if signer is already mapped to the address
                    if (_safesPerSigner[addSigners_[0]].add(avoMultiSafe_) == true) {
                        emit SignerMappingAdded(addSigners_[0], avoMultiSafe_);
                    }
                    // else ignore silently if mapping is already present
                } else {
                    emit SignerMappingAdded(addSigners_[0], avoMultiSafe_);
                }
            } else {
                revert AvoSignersList__InvalidParams();
            }
        } else {
            // get actual signers present at AvoMultisig to make sure data here will be correct
            address[] memory allowedSigners_ = IAvoMultisigV3(avoMultiSafe_).signers();
            uint256 allowedSignersLength_ = allowedSigners_.length;
            // track last allowed signer index for loop performance improvements
            uint256 lastAllowedSignerIndex_;

            // keeping `isAllowedSigner_` outside the loop so it is not re-initialized in each loop -> cheaper
            bool isAllowedSigner_;
            for (uint256 i; i < addSignersLength_; ) {
                // because allowedSigners_ and addSigners_ must be ordered ascending, the for loop can be optimized
                // each new cycle to start from the position where the last signer has been found
                for (uint256 j = lastAllowedSignerIndex_; j < allowedSignersLength_; ) {
                    if (allowedSigners_[j] == addSigners_[i]) {
                        isAllowedSigner_ = true;
                        lastAllowedSignerIndex_ = j + 1; // set to j+1 so that next cycle starts at next array position
                        break;
                    }

                    // could be optimized by checking if allowedSigners_[j] > recoveredSigners_[i]
                    // and immediately skipping with a `break;` if so. Because that implies that the recoveredSigners_[i]
                    // can not be present in allowedSigners_ due to ascending sort.
                    // But that would optimize the failing invalid case and increase cost for the default case where
                    // the input data is valid -> skip.

                    unchecked {
                        ++j;
                    }
                }

                // validate signer trying to add mapping for is really allowed at AvoMultisig
                if (!isAllowedSigner_) {
                    revert AvoSignersList__InvalidParams();
                }

                // reset `isAllowedSigner_` for next loop
                isAllowedSigner_ = false;

                if (trackInStorage) {
                    // `.add()` method also checks if signer is already mapped to the address
                    if (_safesPerSigner[addSigners_[i]].add(avoMultiSafe_) == true) {
                        emit SignerMappingAdded(addSigners_[i], avoMultiSafe_);
                    }
                    // else ignore silently if mapping is already present
                } else {
                    emit SignerMappingAdded(addSigners_[i], avoMultiSafe_);
                }

                unchecked {
                    ++i;
                }
            }
        }
    }

    /// @inheritdoc IAvoSignersList
    function syncRemoveAvoSignerMappings(address avoMultiSafe_, address[] calldata removeSigners_) external {
        // make sure avoMultiSafe_ is an actual AvoMultiSafe
        if (avoFactory.isAvoSafe(avoMultiSafe_) == false) {
            revert AvoSignersList__InvalidParams();
        }

        uint256 removeSignersLength_ = removeSigners_.length;

        if (removeSignersLength_ == 1) {
            // if removing just one signer, using `isSigner()` is cheaper than looping through allowed signers here
            if (IAvoMultisigV3(avoMultiSafe_).isSigner(removeSigners_[0])) {
                revert AvoSignersList__InvalidParams();
            } else {
                if (trackInStorage) {
                    // `.remove()` method also checks if signer is not mapped to the address
                    if (_safesPerSigner[removeSigners_[0]].remove(avoMultiSafe_) == true) {
                        emit SignerMappingRemoved(removeSigners_[0], avoMultiSafe_);
                    }
                    // else ignore silently if mapping is not present
                } else {
                    emit SignerMappingRemoved(removeSigners_[0], avoMultiSafe_);
                }
            }
        } else {
            // get actual signers present at AvoMultisig to make sure data here will be correct
            address[] memory allowedSigners_ = IAvoMultisigV3(avoMultiSafe_).signers();
            uint256 allowedSignersLength_ = allowedSigners_.length;
            // track last signer index where signer to be removed was > allowedSigners for loop performance improvements
            uint256 lastSkipSignerIndex_;

            for (uint256 i; i < removeSignersLength_; ) {
                for (uint256 j = lastSkipSignerIndex_; j < allowedSignersLength_; ) {
                    if (allowedSigners_[j] == removeSigners_[i]) {
                        // validate signer trying to remove mapping for is really not present at AvoMultisig
                        revert AvoSignersList__InvalidParams();
                    }

                    if (allowedSigners_[j] > removeSigners_[i]) {
                        // because allowedSigners_ and removeSigners_ must be ordered ascending the for loop can be optimized:
                        // there is no need to search further once the signer to be removed is < than the allowed signer.
                        // and the next cycle can start from that position
                        lastSkipSignerIndex_ = j;
                        break;
                    }

                    unchecked {
                        ++j;
                    }
                }

                if (trackInStorage) {
                    // `.remove()` method also checks if signer is not mapped to the address
                    if (_safesPerSigner[removeSigners_[i]].remove(avoMultiSafe_) == true) {
                        emit SignerMappingRemoved(removeSigners_[i], avoMultiSafe_);
                    }
                    // else ignore silently if mapping is not present
                } else {
                    emit SignerMappingRemoved(removeSigners_[i], avoMultiSafe_);
                }

                unchecked {
                    ++i;
                }
            }
        }
    }
}

