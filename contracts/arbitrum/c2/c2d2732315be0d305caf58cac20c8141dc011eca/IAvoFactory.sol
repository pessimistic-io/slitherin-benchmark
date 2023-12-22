// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { IAvoVersionsRegistry } from "./IAvoVersionsRegistry.sol";

interface IAvoFactory {
    /// @notice returns AvoVersionsRegistry (proxy) address
    function avoVersionsRegistry() external view returns (IAvoVersionsRegistry);

    /// @notice returns Avo wallet logic contract address that new AvoSafe deployments point to
    function avoWalletImpl() external view returns (address);

    /// @notice returns AvoMultisig logic contract address that new AvoMultiSafe deployments point to
    function avoMultisigImpl() external view returns (address);

    /// @notice           Checks if a certain address is an Avocado smart wallet (AvoSafe or AvoMultisig).
    ///                   Only works for already deployed wallets.
    /// @param avoSafe_   address to check
    /// @return           true if address is an avoSafe
    function isAvoSafe(address avoSafe_) external view returns (bool);

    /// @notice                    Computes the deterministic address for `owner_` based on Create2
    /// @param owner_              AvoSafe owner
    /// @return computedAddress_   computed address for the contract (AvoSafe)
    function computeAddress(address owner_) external view returns (address computedAddress_);

    /// @notice                     Computes the deterministic Multisig address for `owner_` based on Create2
    /// @param owner_               AvoMultiSafe owner
    /// @return computedAddress_    computed address for the contract (AvoSafe)
    function computeAddressMultisig(address owner_) external view returns (address computedAddress_);

    /// @notice         Deploys an AvoSafe for a certain owner deterministcally using Create2.
    ///                 Does not check if contract at address already exists (AvoForwarder does that)
    /// @param owner_   AvoSafe owner
    /// @return         deployed address for the contract (AvoSafe)
    function deploy(address owner_) external returns (address);

    /// @notice                  Deploys a non-default version AvoSafe for an `owner_` deterministcally using Create2.
    ///                          ATTENTION: Only supports AvoWallet version > 2.0.0
    ///                          Does not check if contract at address already exists (AvoForwarder does that)
    /// @param owner_            AvoSafe owner
    /// @param avoWalletVersion_ Version of AvoWallet logic contract to deploy
    /// @return                  deployed address for the contract (AvoSafe)
    function deployWithVersion(address owner_, address avoWalletVersion_) external returns (address);

    /// @notice         Deploys an Avocado Multisig for a certain `owner_` deterministcally using Create2.
    ///                 Does not check if contract at address already exists (AvoForwarder does that)
    /// @param owner_   AvoMultiSafe owner
    /// @return         deployed address for the contract (AvoMultiSafe)
    function deployMultisig(address owner_) external returns (address);

    /// @notice                    Deploys an Avocado Multisig with non-default version for an `owner_`
    ///                            deterministcally using Create2.
    ///                            Does not check if contract at address already exists (AvoForwarder does that)
    /// @param owner_              AvoMultiSafe owner
    /// @param avoMultisigVersion_ Version of AvoMultisig logic contract to deploy
    /// @return                    deployed address for the contract (AvoMultiSafe)
    function deployMultisigWithVersion(address owner_, address avoMultisigVersion_) external returns (address);

    /// @notice                registry can update the current AvoWallet implementation contract set as default
    ///                        `_avoWalletImpl` logic contract address for new deployments
    /// @param avoWalletImpl_  the new avoWalletImpl address
    function setAvoWalletImpl(address avoWalletImpl_) external;

    /// @notice                 registry can update the current AvoMultisig implementation contract set as default
    ///                         `_avoMultisigImpl` logic contract address for new deployments
    /// @param avoMultisigImpl_ the new avoWalletImpl address
    function setAvoMultisigImpl(address avoMultisigImpl_) external;

    /// @notice returns the byteCode for the AvoSafe contract used for Create2 address computation
    function avoSafeBytecode() external view returns (bytes32);

    /// @notice returns the byteCode for the AvoMultiSafe contract used for Create2 address computation
    function avoMultiSafeBytecode() external view returns (bytes32);
}

