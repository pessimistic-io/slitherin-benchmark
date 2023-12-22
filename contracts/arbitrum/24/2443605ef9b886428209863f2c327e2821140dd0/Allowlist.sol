// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Errors.sol";
import "./IAllowlist.sol";
import "./Initializable.sol";
import "./Ownable2Step.sol";
import "./Sets.sol";
import "./Checker.sol";

/// @title  Allowlist
/// @author Savvy DeFi
contract Allowlist is IAllowlist, Ownable2Step, Initializable {
    using Sets for Sets.AddressSet;
    Sets.AddressSet addresses;

    /// @inheritdoc IAllowlist
    bool public override disabled;

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        _transferOwnership(_msgSender());
    }

    /// @inheritdoc IAllowlist
    function getAddresses() external view returns (address[] memory) {
        return addresses.values;
    }

    /// @inheritdoc IAllowlist
    function add(address caller) external override {
        _onlyAdmin();
        Checker.checkState(!disabled, "add allowlist is disabled");
        addresses.add(caller);
        emit AccountAdded(caller);
    }

    /// @inheritdoc IAllowlist
    function remove(address caller) external override {
        _onlyAdmin();
        Checker.checkState(!disabled, "add allowlist is disabled");
        addresses.remove(caller);
        emit AccountRemoved(caller);
    }

    /// @inheritdoc IAllowlist
    function disable() external override {
        _onlyAdmin();
        disabled = true;
        emit AllowlistDisabled();
    }

    /// @inheritdoc IAllowlist
    function isAllowed(address account) external view override returns (bool) {
        return disabled || addresses.contains(account);
    }

    /// @dev Reverts if the caller is not the contract owner.
    function _onlyAdmin() internal view {
        require(msg.sender == owner(), "Unauthorized");
    }
}

