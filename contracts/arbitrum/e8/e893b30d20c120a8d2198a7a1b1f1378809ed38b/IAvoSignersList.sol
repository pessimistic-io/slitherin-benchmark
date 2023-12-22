// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IAvoSignersList {
    /// @notice adds mappings of `addSigners_` to an AvoMultiSafe `avoMultiSafe_`.
    ///         checks the data present at the AvoMultisig to validate input data.
    ///
    /// If `trackInStorage` flag is set to false, then only an event will be emitted for off-chain tracking.
    /// The contract itself will not track avoMultiSafes per signer on-chain!
    ///
    /// Silently ignores `addSigners_` that are already added
    ///
    /// There is expectedly no need for this method to be called by anyone other than the AvoMultisig itself.
    function syncAddAvoSignerMappings(address avoMultiSafe_, address[] calldata addSigners_) external;

    /// @notice removes mappings of `removeSigners_` from an AvoMultiSafe `avoMultiSafe_`.
    ///         checks the data present at the AvoMultisig to validate input data.
    ///
    /// If `trackInStorage` flag is set to false, then only an event will be emitted for off-chain tracking.
    /// The contract itself will not track avoMultiSafes per signer on-chain!
    ///
    /// Silently ignores `addSigners_` that are already removed
    ///
    /// There is expectedly no need for this method to be called by anyone other than the AvoMultisig itself.
    function syncRemoveAvoSignerMappings(address avoMultiSafe_, address[] calldata removeSigners_) external;
}

