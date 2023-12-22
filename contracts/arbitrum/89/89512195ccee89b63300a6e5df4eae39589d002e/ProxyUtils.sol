// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./AddressUpgradeable.sol";
import "./StorageSlotUpgradeable.sol";

/// @title ProxyUtils
/// @notice Common code for `Proxy` and underlying implementation contracts.
contract ProxyUtils {
    /// @dev Storage slot with the address of the current implementation.
    /// This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
    /// validated in the constructor.
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev Emitted when the implementation is upgraded.
    event Upgraded(address indexed implementation);

    /// @dev Returns the current implementation address.
    function _implementation() internal view returns (address impl) {
        return StorageSlotUpgradeable.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    /// @dev Perform implementation upgrade
    /// Emits an {Upgraded} event.
    function _upgradeTo(address newImplementation) internal {
        require(AddressUpgradeable.isContract(newImplementation), "ERC1967: new implementation is not a contract");
        StorageSlotUpgradeable.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
        emit Upgraded(newImplementation);
    }

    /// @dev Perform implementation upgrade with additional setup call.
    /// Emits an {Upgraded} event.
    function _upgradeToAndCall(
        address newImplementation,
        bytes memory data,
        bool forceCall
    ) internal {
        _upgradeTo(newImplementation);
        if (data.length > 0 || forceCall) {
            _functionDelegateCall(newImplementation, data);
        }
    }

    /// @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
    /// but performing a delegate call.
    function _functionDelegateCall(address target, bytes memory data) private returns (bytes memory) {
        require(AddressUpgradeable.isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return AddressUpgradeable.verifyCallResult(success, returndata, "Address: low-level delegate call failed");
    }
}

