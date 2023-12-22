// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IAvoAuthoritiesList {
    /// @notice syncs mappings of `authorities_` to an AvoSafe `avoSafe_` based on the data present at the wallet.
    /// If `trackInStorage` flag is set to false, then only an event will be emitted for off-chain tracking.
    /// The contract itself will not track avoSafes per authority on-chain!
    ///
    /// Silently ignores `authorities_` that are already mapped correctly.
    ///
    /// There is expectedly no need for this method to be called by anyone other than the AvoSafe itself.
    ///
    /// @dev Note that in off-chain tracking make sure to check for duplicates (i.e. mapping already exists).
    /// This should not happen but when not tracking the data on-chain there is no way to be sure.
    function syncAvoAuthorityMappings(address avoSafe_, address[] calldata authorities_) external;
}

