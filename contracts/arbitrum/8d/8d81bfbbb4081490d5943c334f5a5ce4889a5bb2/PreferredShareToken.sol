// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {WrappedShareToken, IERC20Metadata, Authority} from "./WrappedShareToken.sol";
import {IShareRight} from "./IShareRight.sol";

import {EnumerableSet} from "./EnumerableSet.sol";

/// @notice Wrapped ERC20 with share rights.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/PreferredShareToken.sol)
// slither-disable-next-line unimplemented-functions
contract PreferredShareToken is WrappedShareToken {
    using EnumerableSet for EnumerableSet.AddressSet;

    error PreferredShareToken__NoArrayParity();
    error PreferredShareToken__TermNotFound();
    error PreferredShareToken__ZeroAddress();

    event RightsAmended(address[] rights, bytes[] rightsData);

    EnumerableSet.AddressSet private _terms;

    constructor(
        string memory _name,
        string memory _symbol,
        IERC20Metadata _underlying,
        uint256 _multiple,
        address _owner,
        Authority _authority
    ) WrappedShareToken(_name, _symbol, _underlying, _multiple, _owner, _authority) {}

    function getTerms() external view returns (address[] memory) {
        return _terms.values();
    }

    function amendRights(address[] calldata rights, bytes[] calldata rightsData) external requiresAuth {
        _validateRights(rights, rightsData);

        for (uint256 i = 0; i < rights.length; i++) {
            if (rightsData[i].length == 0) {
                // Remove term from agreement
                bool removed = _terms.remove(rights[i]);
                if (!removed) revert PreferredShareToken__TermNotFound();
                // Cancel removed term
                IShareRight(rights[i]).removeRight(address(this));
            } else {
                // Update Term
                if (!_terms.add(rights[i])) {
                    // Existing term. Cancel
                    IShareRight(rights[i]).removeRight(address(this));
                }
                // Create term with new data
                IShareRight(rights[i]).createRight(address(this), rightsData[i]);
            }
        }

        emit RightsAmended(rights, rightsData);
    }

    function _validateRights(address[] calldata rights, bytes[] calldata rightsData) internal pure {
        if (rights.length != rightsData.length) revert PreferredShareToken__NoArrayParity();
        for (uint256 i = 0; i < rights.length; i++) {
            if (address(rights[i]) == address(0)) revert PreferredShareToken__ZeroAddress();
        }
    }
}

