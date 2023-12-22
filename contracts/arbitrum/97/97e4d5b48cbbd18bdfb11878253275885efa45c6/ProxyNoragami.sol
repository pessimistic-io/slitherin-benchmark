// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC1967Proxy.sol";
import "./IERC1967.sol";

contract ProxyNoragami is ERC1967Proxy{
    // An immutable address for the admin avoid unnecessary SLOADs before each call
    // at the expense of removing the ability to change the admin once it's set.
    // This is acceptable if the admin is always a ProxyAdmin instance or similar contract
    // with its own ability to transfer the permissions to another account.

    /**
     * @dev The proxy caller is the current admin, and can't fallback to the proxy target.
     */
    error ProxyDeniedAdminAccess();

    /**
     * @dev msg.value is not 0.
     */
    error ProxyNonPayableFunction();

    /**
     * @dev Initializes an upgradeable proxy managed by `_admin`, backed by the implementation at `_logic`, and
     * optionally initialized with `_data` as explained in {ERC1967Proxy-constructor}.
     */
    constructor(address _logic, bytes memory _data) payable ERC1967Proxy(_logic, _data) {}

    /**
     * @dev Upgrade the implementation of the proxy.
     */
    function _dispatchUpgradeTo() private returns (bytes memory) {
        _requireZeroValue();

        address newImplementation = abi.decode(msg.data[4:], (address));
        ERC1967Utils.upgradeToAndCall(newImplementation, bytes(""), false);

        return "";
    }

    /**
     * @dev Upgrade the implementation of the proxy, and then call a function from the new implementation as specified
     * by `data`, which should be an encoded function call. This is useful to initialize new storage variables in the
     * proxied contract.
     */
    function _dispatchUpgradeToAndCall() private returns (bytes memory) {
        (address newImplementation, bytes memory data) = abi.decode(msg.data[4:], (address, bytes));
        ERC1967Utils.upgradeToAndCall(newImplementation, data, true);

        return "";
    }

    /**
     * @dev To keep this contract fully transparent, the fallback is payable. This helper is here to enforce
     * non-payability of function implemented through dispatchers while still allowing value to pass through.
     */
    function _requireZeroValue() private {
        if (msg.value != 0) {
            revert ProxyNonPayableFunction();
        }
    }
}
