// SPDX-License-Identifier: LGPL-3.0-only
// Created By: Art Blocks Inc.

// @dev fixed to specific solidity version for clarity and for more clear
// source code verification purposes.
pragma solidity 0.8.19;

import {IGenArt721CoreContractV3_Base} from "./IGenArt721CoreContractV3_Base.sol";
import {IDelegationRegistry} from "./IDelegationRegistry.sol";
import {ISharedMinterV0} from "./ISharedMinterV0.sol";
import {ISharedMinterHolderERC20V0} from "./ISharedMinterHolderERC20V0.sol";
import {IMinterFilterV1} from "./IMinterFilterV1.sol";

import {AuthLib} from "./AuthLib.sol";
import {SplitFundsLib} from "./SplitFundsLib.sol";
import {MaxInvocationsLib} from "./MaxInvocationsLib.sol";
import {SetPriceLib} from "./SetPriceLib.sol";
import {TokenHolderLib} from "./TokenHolderLib.sol";
import {PolyptychLib} from "./PolyptychLib.sol";

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {EnumerableSet} from "./EnumerableSet.sol";

/**
 * @title Shared, filtered Minter contract that allows tokens to be minted with
 * an artist-configured ERC20 token when purchaser owns an allowlisted ERC-721
 * NFT.
 * This contract must be used with an accompanying shared randomizer contract
 * that is configured to copy the token hash seed from the allowlisted token to
 * a corresponding newly-minted token. This minter contract must be the allowed
 * hash seed setter contract for the shared randomizer contract.
 * The source token may only be used to mint one additional polyptych "panel" if the token
 * has not yet been used to mint a panel with the currently configured panel ID. To add
 * an additional panel to a project, the panel ID may be incremented for the project
 * using the `incrementPolyptychProjectPanelId` function. Panel IDs for a project may only
 * be incremented such that panels must be minted in the order of their panel ID. Tokens
 * of the same project and panel ID may be minted in any order.
 * This is designed to be used with IGenArt721CoreContractExposesHashSeed contracts with an
 * active ISharedRandomizerV0 randomizer available for this minter to use.
 * This minter requires both a properly configured core contract and shared
 * randomizer in order to mint polyptych tokens.
 * @author Art Blocks Inc.
 * @notice Privileged Roles and Ownership:
 * This contract is designed to be managed, with limited powers.
 * Privileged roles and abilities are controlled by the project's artist, which
 * can be modified by the core contract's Admin ACL contract. Both of these
 * roles hold extensive power and can modify minter details.
 * Care must be taken to ensure that the admin ACL contract and artist
 * addresses are secure behind a multi-sig or other access control mechanism.
 * ----------------------------------------------------------------------------
 * The following functions are restricted to a project's artist:
 * - updatePricePerTokenInWei
 * - syncProjectMaxInvocationsToCore
 * - manuallyLimitProjectMaxInvocations
 * - updateProjectCurrencyInfo
 * - allowHoldersOfProjects
 * - removeHoldersOfProjects
 * - allowAndRemoveHoldersOfProjects
 * - incrementPolyptychProjectPanelId
 * ----------------------------------------------------------------------------
 * Additional admin and artist privileged roles may be described on other
 * contracts that this minter integrates with.
 * ----------------------------------------------------------------------------
 * This contract allows vaults to configure token-level or wallet-level
 * delegation of minting privileges. This allows a vault on an allowlist to
 * delegate minting privileges to a wallet that is not on the allowlist,
 * enabling the vault to remain air-gapped while still allowing minting. The
 * delegation registry contract is responsible for managing these delegations,
 * and is available at the address returned by the public immutable
 * `delegationRegistryAddress`. At the time of writing, the delegation
 * registry enables easy delegation configuring at https://delegate.cash/.
 * Art Blocks does not guarentee the security of the delegation registry, and
 * users should take care to ensure that the delegation registry is secure.
 * Token-level delegations are configured by the vault owner, and contract-
 * level delegations must be configured for the core token contract as returned
 * by the public immutable variable `genArt721CoreAddress`.
 * ----------------------------------------------------------------------------
 * @notice Caution: While Engine projects must be registered on the Art Blocks
 * Core Registry to assign this minter, this minter does not enforce that a
 * project is registered when configured or queried. This is primarily for gas
 * optimization purposes. It is, therefore, possible that fake projects may be
 * configured on this minter, but they will not be able to mint tokens due to
 * checks performed by this minter's Minter Filter.
 */
contract MinterSetPricePolyptychERC20V5 is
    ReentrancyGuard,
    ISharedMinterV0,
    ISharedMinterHolderERC20V0
{
    // add Enumerable Set methods
    using EnumerableSet for EnumerableSet.AddressSet;

    /// Minter filter address this minter interacts with
    address public immutable minterFilterAddress;

    /// Minter filter this minter may interact with.
    IMinterFilterV1 private immutable _minterFilter;

    /// Delegation registry address
    address public immutable delegationRegistryAddress;

    /// Delegation registry address
    IDelegationRegistry private immutable _delegationRegistryContract;

    /// minterType for this minter
    string public constant minterType = "MinterSetPricePolyptychERC20V5";

    /// minter version for this minter
    string public constant minterVersion = "v5.0.0";

    uint256 internal constant ONE_MILLION = 1_000_000;

    // MODIFIERS
    // @dev contract uses modifier-like internal functions instead of modifiers
    // to reduce contract bytecode size
    // @dev contract uses AuthLib for some modifier-like functions

    /**
     * @notice Initializes contract to be a Filtered Minter for
     * `minterFilter` minter filter.
     * @param minterFilter Minter filter for which this will be a
     * filtered minter.
     * @param delegationRegistryAddress_ Delegation registry contract address.
     */
    constructor(
        address minterFilter,
        address delegationRegistryAddress_
    ) ReentrancyGuard() {
        minterFilterAddress = minterFilter;
        _minterFilter = IMinterFilterV1(minterFilter);

        delegationRegistryAddress = delegationRegistryAddress_;
        _delegationRegistryContract = IDelegationRegistry(
            delegationRegistryAddress_
        );
        emit TokenHolderLib.DelegationRegistryUpdated(
            delegationRegistryAddress_
        );
    }

    /**
     * @notice Manually sets the local maximum invocations of project `projectId`
     * with the provided `maxInvocations`, checking that `maxInvocations` is less
     * than or equal to the value of project `project_id`'s maximum invocations that is
     * set on the core contract.
     * @dev Note that a `maxInvocations` of 0 can only be set if the current `invocations`
     * value is also 0 and this would also set `maxHasBeenInvoked` to true, correctly short-circuiting
     * this minter's purchase function, avoiding extra gas costs from the core contract's maxInvocations check.
     * @param projectId Project ID to set the maximum invocations for.
     * @param coreContract Core contract address for the given project.
     * @param maxInvocations Maximum invocations to set for the project.
     */
    function manuallyLimitProjectMaxInvocations(
        uint256 projectId,
        address coreContract,
        uint24 maxInvocations
    ) external {
        AuthLib.onlyArtist({
            projectId: projectId,
            coreContract: coreContract,
            sender: msg.sender
        });
        MaxInvocationsLib.manuallyLimitProjectMaxInvocations({
            projectId: projectId,
            coreContract: coreContract,
            maxInvocations: maxInvocations
        });
    }

    /**
     * @notice Updates this minter's price per token of project `projectId`
     * to be `pricePerTokenInWei`. Note that "in wei" is a misnomer on this
     * ERC20 minter, but is used for consistency with the ETH minters. The
     * price value represents the ERC20 token price in base units.
     * @dev Note that it is intentionally supported here that the configured
     * price may be explicitly set to `0`.
     * @dev Note that it is intentionally supported here that the configured
     * price may be explicitly set to `0`.
     * @param projectId Project ID to set the price per token for.
     * @param coreContract Core contract address for the given project.
     * @param pricePerTokenInWei Price per token to set for the project.
     * Represents the ERC20 token price in base units. For example, if the
     * ERC20 token has 6 decimals, an input value of `1_000_000` would
     * represent a price of `1.000000` tokens.
     */
    function updatePricePerTokenInWei(
        uint256 projectId,
        address coreContract,
        uint248 pricePerTokenInWei
    ) external {
        AuthLib.onlyArtist({
            projectId: projectId,
            coreContract: coreContract,
            sender: msg.sender
        });
        SetPriceLib.updatePricePerToken({
            projectId: projectId,
            coreContract: coreContract,
            pricePerToken: pricePerTokenInWei
        });

        // for convenience, sync local max invocations to the core contract if
        // and only if max invocations have not already been synced.
        // @dev do not sync if max invocations have already been synced, as
        // local max invocations could have been manually set to be
        // intentionally less than the core contract's max invocations.
        // @dev if local maxInvocations and maxHasBeenInvoked are both
        // initial values, we know they have not been populated on this minter
        if (
            MaxInvocationsLib.maxInvocationsIsUnconfigured({
                projectId: projectId,
                coreContract: coreContract
            })
        ) {
            MaxInvocationsLib.syncProjectMaxInvocationsToCore({
                projectId: projectId,
                coreContract: coreContract
            });
        }
    }

    /**
     * @notice Updates payment currency of project `projectId` on core
     * contract `coreContract` to be `currencySymbol` at address
     * `currencyAddress`.
     * Only supports ERC20 tokens - for ETH minting, use a different minter.
     * Resets price to be unconfigured if currency was previously configured,
     * as a safeguard against accidentally setting a price in one currency
     * and then changing the currency but not the price.
     * @dev nonReentrant because no reentrant use cases, and to eliminate an
     * entire branch of reentrancy attack vectors.
     * @param projectId Project ID to update.
     * @param coreContract Core contract address for the given project.
     * @param currencySymbol Currency symbol.
     * @param currencyAddress Currency address.
     */
    function updateProjectCurrencyInfo(
        uint256 projectId,
        address coreContract,
        string memory currencySymbol,
        address currencyAddress
    ) external nonReentrant {
        AuthLib.onlyArtist({
            projectId: projectId,
            coreContract: coreContract,
            sender: msg.sender
        });
        bool recommendPriceReset = SplitFundsLib
            .updateProjectCurrencyInfoERC20({
                projectId: projectId,
                coreContract: coreContract,
                currencySymbol: currencySymbol,
                currencyAddress: currencyAddress
            });
        if (recommendPriceReset) {
            SetPriceLib.resetPricePerToken({
                projectId: projectId,
                coreContract: coreContract
            });
        }
    }

    /**
     * @notice Allows holders of NFTs at addresses `ownedNFTAddresses`,
     * project IDs `ownedNFTProjectIds` to mint on project `projectId`.
     * `ownedNFTAddresses` assumed to be aligned with `ownedNFTProjectIds`.
     * e.g. Allows holders of project `ownedNFTProjectIds[0]` on token
     * contract `ownedNFTAddresses[0]` to mint `projectId`.
     * WARNING: Only Art Blocks Core contracts are compatible with holder allowlisting,
     * due to assumptions about tokenId and projectId relationships.
     * @param projectId Project ID to enable minting on.
     * @param coreContract Core contract address for the given project.
     * @param ownedNFTAddresses NFT core addresses of projects to be
     * allowlisted. Indexes must align with `ownedNFTProjectIds`.
     * @param ownedNFTProjectIds Project IDs on `ownedNFTAddresses` whose
     * holders shall be allowlisted to mint project `projectId`. Indexes must
     * align with `ownedNFTAddresses`.
     */
    function allowHoldersOfProjects(
        uint256 projectId,
        address coreContract,
        address[] calldata ownedNFTAddresses,
        uint256[] calldata ownedNFTProjectIds
    ) external {
        AuthLib.onlyArtist({
            projectId: projectId,
            coreContract: coreContract,
            sender: msg.sender
        });
        TokenHolderLib.allowHoldersOfProjects({
            projectId: projectId,
            coreContract: coreContract,
            ownedNFTAddresses: ownedNFTAddresses,
            ownedNFTProjectIds: ownedNFTProjectIds
        });
    }

    /**
     * @notice Removes holders of NFTs at addresses `ownedNFTAddresses`,
     * project IDs `ownedNFTProjectIds` to mint on project `projectId`. If
     * other projects owned by a holder are still allowed to mint, holder will
     * maintain ability to purchase.
     * `ownedNFTAddresses` assumed to be aligned with `ownedNFTProjectIds`.
     * e.g. Removes holders of project `ownedNFTProjectIds[0]` on token
     * contract `ownedNFTAddresses[0]` from mint allowlist of `projectId`.
     * @param projectId Project ID to enable minting on.
     * @param coreContract Core contract address for the given project.
     * @param ownedNFTAddresses NFT core addresses of projects to be removed
     * from allowlist. Indexes must align with `ownedNFTProjectIds`.
     * @param ownedNFTProjectIds Project IDs on `ownedNFTAddresses` whose
     * holders will be removed from allowlist to mint project `projectId`.
     * Indexes must align with `ownedNFTAddresses`.
     */
    function removeHoldersOfProjects(
        uint256 projectId,
        address coreContract,
        address[] calldata ownedNFTAddresses,
        uint256[] calldata ownedNFTProjectIds
    ) external {
        AuthLib.onlyArtist({
            projectId: projectId,
            coreContract: coreContract,
            sender: msg.sender
        });
        // require same length arrays
        TokenHolderLib.removeHoldersOfProjects({
            projectId: projectId,
            coreContract: coreContract,
            ownedNFTAddresses: ownedNFTAddresses,
            ownedNFTProjectIds: ownedNFTProjectIds
        });
    }

    /**
     * @notice Allows holders of NFTs at addresses `ownedNFTAddressesAdd`,
     * project IDs `ownedNFTProjectIdsAdd` to mint on project `projectId`.
     * Also removes holders of NFTs at addresses `ownedNFTAddressesRemove`,
     * project IDs `ownedNFTProjectIdsRemove` from minting on project
     * `projectId`.
     * `ownedNFTAddressesAdd` assumed to be aligned with
     * `ownedNFTProjectIdsAdd`.
     * e.g. Allows holders of project `ownedNFTProjectIdsAdd[0]` on token
     * contract `ownedNFTAddressesAdd[0]` to mint `projectId`.
     * `ownedNFTAddressesRemove` also assumed to be aligned with
     * `ownedNFTProjectIdsRemove`.
     * WARNING: Only Art Blocks Core contracts are compatible with holder allowlisting,
     * due to assumptions about tokenId and projectId relationships.
     * @param projectId Project ID to enable minting on.
     * @param coreContract Core contract address for the given project.
     * @param ownedNFTAddressesAdd NFT core addresses of projects to be
     * allowlisted. Indexes must align with `ownedNFTProjectIdsAdd`.
     * @param ownedNFTProjectIdsAdd Project IDs on `ownedNFTAddressesAdd`
     * whose holders shall be allowlisted to mint project `projectId`. Indexes
     * must align with `ownedNFTAddressesAdd`.
     * @param ownedNFTAddressesRemove NFT core addresses of projects to be
     * removed from allowlist. Indexes must align with
     * `ownedNFTProjectIdsRemove`.
     * @param ownedNFTProjectIdsRemove Project IDs on
     * `ownedNFTAddressesRemove` whose holders will be removed from allowlist
     * to mint project `projectId`. Indexes must align with
     * `ownedNFTAddressesRemove`.
     * @dev if a project is included in both add and remove arrays, it will be
     * removed.
     */
    function allowAndRemoveHoldersOfProjects(
        uint256 projectId,
        address coreContract,
        address[] calldata ownedNFTAddressesAdd,
        uint256[] calldata ownedNFTProjectIdsAdd,
        address[] calldata ownedNFTAddressesRemove,
        uint256[] calldata ownedNFTProjectIdsRemove
    ) external {
        AuthLib.onlyArtist({
            projectId: projectId,
            coreContract: coreContract,
            sender: msg.sender
        });
        TokenHolderLib.allowAndRemoveHoldersOfProjects({
            projectId: projectId,
            coreContract: coreContract,
            ownedNFTAddressesAdd: ownedNFTAddressesAdd,
            ownedNFTProjectIdsAdd: ownedNFTProjectIdsAdd,
            ownedNFTAddressesRemove: ownedNFTAddressesRemove,
            ownedNFTProjectIdsRemove: ownedNFTProjectIdsRemove
        });
    }

    /**
     * @notice Allows the artist to increment the minter to the next polyptych panel
     * @param projectId Project ID to increment to its next polyptych panel
     * @param coreContract Core contract address for the given project.
     */
    function incrementPolyptychProjectPanelId(
        uint256 projectId,
        address coreContract
    ) public {
        AuthLib.onlyArtist({
            projectId: projectId,
            coreContract: coreContract,
            sender: msg.sender
        });
        PolyptychLib.incrementPolyptychProjectPanelId({
            projectId: projectId,
            coreContract: coreContract
        });
    }

    /**
     * @notice Purchases a token from project `projectId` on core contract
     * `coreContract` using an owned NFT at address `ownedNFTAddress` and
     * token ID `ownedNFTTokenId` as the parent token.
     * @param projectId Project ID to mint a token on.
     * @param coreContract Core contract address for the given project.
     * @param maxPricePerToken Maximum price of token being allowed by the
     * purchaser, in base units. For example, if the ERC20 token has 6
     * decimals, an input value of `1_000_000` would represent a maximum price
     * of `1.000000` tokens.
     * @param currencyAddress Currency address of token.
     * @param ownedNFTAddress ERC-721 NFT address holding the project token
     * owned by msg.sender being used as the parent token.
     * @param ownedNFTTokenId ERC-721 NFT token ID owned by msg.sender to be
     * used as the parent token.
     * @return tokenId Token ID of minted token
     */
    function purchase(
        uint256 projectId,
        address coreContract,
        uint256 maxPricePerToken,
        address currencyAddress,
        address ownedNFTAddress,
        uint256 ownedNFTTokenId
    ) external returns (uint256 tokenId) {
        tokenId = purchaseTo({
            to: msg.sender,
            projectId: projectId,
            coreContract: coreContract,
            maxPricePerToken: maxPricePerToken,
            currencyAddress: currencyAddress,
            ownedNFTAddress: ownedNFTAddress,
            ownedNFTTokenId: ownedNFTTokenId,
            vault: address(0)
        });
        return tokenId;
    }

    /**
     * @notice Purchases a token from project `projectId` on core contract
     * `coreContract` using an owned NFT at address `ownedNFTAddress` and
     * token ID `ownedNFTTokenId` as the parent token.
     * Sets the token's owner to `to`.
     * @param to Address to be the new token's owner.
     * @param projectId Project ID to mint a token on.
     * @param coreContract Core contract address for the given project.
     * @param maxPricePerToken Maximum price of token being allowed by the
     * purchaser, in base units. For example, if the ERC20 token has 6
     * decimals, an input value of `1_000_000` would represent a maximum price
     * of `1.000000` tokens.
     * @param currencyAddress Currency address of token.
     * @param ownedNFTAddress ERC-721 NFT holding the project token owned by
     * msg.sender being used as the parent token.
     * @param ownedNFTTokenId ERC-721 NFT token ID owned by msg.sender being used
     * as the parent token.
     * @return tokenId Token ID of minted token
     */
    function purchaseTo(
        address to,
        uint256 projectId,
        address coreContract,
        uint256 maxPricePerToken,
        address currencyAddress,
        address ownedNFTAddress,
        uint256 ownedNFTTokenId
    ) external returns (uint256 tokenId) {
        return
            purchaseTo({
                to: to,
                projectId: projectId,
                coreContract: coreContract,
                maxPricePerToken: maxPricePerToken,
                currencyAddress: currencyAddress,
                ownedNFTAddress: ownedNFTAddress,
                ownedNFTTokenId: ownedNFTTokenId,
                vault: address(0)
            });
    }

    // public getter functions
    /**
     * @notice Gets the maximum invocations project configuration.
     * @param projectId The ID of the project whose data needs to be fetched.
     * @param coreContract The address of the core contract.
     * @return MaxInvocationsLib.MaxInvocationsProjectConfig instance with the
     * configuration data.
     */
    function maxInvocationsProjectConfig(
        uint256 projectId,
        address coreContract
    )
        external
        view
        returns (MaxInvocationsLib.MaxInvocationsProjectConfig memory)
    {
        return
            MaxInvocationsLib.getMaxInvocationsProjectConfig({
                projectId: projectId,
                coreContract: coreContract
            });
    }

    /**
     * @notice Gets the set price project configuration.
     * @param projectId The ID of the project whose data needs to be fetched.
     * @param coreContract The address of the core contract.
     * @return SetPriceProjectConfig struct with the fixed price project
     * configuration data.
     */
    function setPriceProjectConfig(
        uint256 projectId,
        address coreContract
    ) external view returns (SetPriceLib.SetPriceProjectConfig memory) {
        return
            SetPriceLib.getSetPriceProjectConfig({
                projectId: projectId,
                coreContract: coreContract
            });
    }

    /**
     * @notice Checks if a specific NFT owner is allowed in a given project.
     * @dev This function retrieves the allowance status of an NFT owner
     * within a specific project from the allowedProjectHoldersMapping.
     * @param projectId The ID of the project to check.
     * @param coreContract Core contract address for the given project.
     * @param ownedNFTAddress The address of the owned NFT contract.
     * @param ownedNFTProjectId The ID of the owned NFT project.
     * @return bool True if the NFT owner is allowed in the given project, False otherwise.
     */
    function allowedProjectHolders(
        uint256 projectId,
        address coreContract,
        address ownedNFTAddress,
        uint256 ownedNFTProjectId
    ) external view returns (bool) {
        return
            TokenHolderLib
                .getHolderProjectConfig({
                    projectId: projectId,
                    coreContract: coreContract
                })
                .allowedProjectHolders[ownedNFTAddress][ownedNFTProjectId];
    }

    /**
     * @notice Returns if token is an allowlisted NFT for project `projectId`.
     * @param projectId Project ID to be checked.
     * @param coreContract Core contract address for the given project.
     * @param ownedNFTAddress ERC-721 NFT token address to be checked.
     * @param ownedNFTTokenId ERC-721 NFT token ID to be checked.
     * @return bool Token is allowlisted
     * @dev does not check if token has been used to purchase
     * @dev assumes project ID can be derived from tokenId / 1_000_000
     */
    function isAllowlistedNFT(
        uint256 projectId,
        address coreContract,
        address ownedNFTAddress,
        uint256 ownedNFTTokenId
    ) external view returns (bool) {
        return
            TokenHolderLib.isAllowlistedNFT({
                projectId: projectId,
                coreContract: coreContract,
                ownedNFTAddress: ownedNFTAddress,
                ownedNFTTokenId: ownedNFTTokenId
            });
    }

    /**
     * @notice Checks if the specified `coreContract` is a valid engine contract.
     * @dev This function retrieves the cached value of `isEngine` from
     * the `isEngineCache` mapping. If the cached value is already set, it
     * returns the cached value. Otherwise, it calls the `getV3CoreIsEngineView`
     * function from the `SplitFundsLib` library to check if `coreContract`
     * is a valid engine contract.
     * @dev This function will revert if the provided `coreContract` is not
     * a valid Engine or V3 Flagship contract.
     * @param coreContract The address of the contract to check.
     * @return bool indicating if `coreContract` is a valid engine contract.
     */
    function isEngineView(address coreContract) external view returns (bool) {
        SplitFundsLib.IsEngineCache storage isEngineCache = SplitFundsLib
            .getIsEngineCacheConfig(coreContract);
        if (isEngineCache.isCached) {
            return isEngineCache.isEngine;
        } else {
            // @dev this calls the non-state-modifying variant of isEngine
            return SplitFundsLib.getV3CoreIsEngineView(coreContract);
        }
    }

    /**
     * @notice projectId => has project reached its maximum number of
     * invocations? Note that this returns a local cache of the core contract's
     * state, and may be out of sync with the core contract. This is
     * intentional, as it only enables gas optimization of mints after a
     * project's maximum invocations has been reached. A false negative will
     * only result in a gas cost increase, since the core contract will still
     * enforce a maxInvocation check during minting. A false positive is not
     * possible because the V3 core contract only allows maximum invocations
     * to be reduced, not increased. Based on this rationale, we intentionally
     * do not do input validation in this method as to whether or not the input
     * @param projectId is an existing project ID.
     * @param coreContract is an existing core contract address.
     */
    function projectMaxHasBeenInvoked(
        uint256 projectId,
        address coreContract
    ) external view returns (bool) {
        return
            MaxInvocationsLib.getMaxHasBeenInvoked({
                projectId: projectId,
                coreContract: coreContract
            });
    }

    /**
     * @notice projectId => project's maximum number of invocations.
     * Optionally synced with core contract value, for gas optimization.
     * Note that this returns a local cache of the core contract's
     * state, and may be out of sync with the core contract. This is
     * intentional, as it only enables gas optimization of mints after a
     * project's maximum invocations has been reached.
     * @dev A number greater than the core contract's project max invocations
     * will only result in a gas cost increase, since the core contract will
     * still enforce a maxInvocation check during minting. A number less than
     * the core contract's project max invocations is only possible when the
     * project's max invocations have not been synced on this minter, since the
     * V3 core contract only allows maximum invocations to be reduced, not
     * increased. When this happens, the minter will enable minting, allowing
     * the core contract to enforce the max invocations check. Based on this
     * rationale, we intentionally do not do input validation in this method as
     * to whether or not the input `projectId` is an existing project ID.
     * @param projectId is an existing project ID.
     * @param coreContract is an existing core contract address.
     */
    function projectMaxInvocations(
        uint256 projectId,
        address coreContract
    ) external view returns (uint256) {
        return
            MaxInvocationsLib.getMaxInvocations({
                projectId: projectId,
                coreContract: coreContract
            });
    }

    /**
     * @notice Gets your balance of the ERC20 token currently set
     * as the payment currency for project `projectId` in the core
     * contract `coreContract`.
     * @param projectId Project ID to be queried.
     * @param coreContract The address of the core contract.
     * @return balance Balance of ERC20
     */
    function getYourBalanceOfProjectERC20(
        uint256 projectId,
        address coreContract
    ) external view returns (uint256 balance) {
        (address currencyAddress, ) = SplitFundsLib.getCurrencyInfoERC20(
            projectId,
            coreContract
        );
        balance = SplitFundsLib.getERC20Balance({
            currencyAddress: currencyAddress,
            walletAddress: msg.sender
        });
        return balance;
    }

    /**
     * @notice Gets your allowance for this minter of the ERC20
     * token currently set as the payment currency for project
     * `projectId`.
     * @param projectId Project ID to be queried.
     * @param coreContract The address of the core contract.
     * @return remaining Remaining allowance of ERC20
     */
    function checkYourAllowanceOfProjectERC20(
        uint256 projectId,
        address coreContract
    ) external view returns (uint256 remaining) {
        (address currencyAddress, ) = SplitFundsLib.getCurrencyInfoERC20({
            projectId: projectId,
            coreContract: coreContract
        });
        remaining = SplitFundsLib.getERC20Allowance({
            currencyAddress: currencyAddress,
            walletAddress: msg.sender,
            spenderAddress: address(this)
        });
        return remaining;
    }

    /**
     * @notice Gets if price of token is configured, price of minting a
     * token on project `projectId`, and currency symbol and address to be
     * used as payment.
     * `isConfigured` is only true if a price has been configured, and an ERC20
     * token has been configured.
     * @param projectId Project ID to get price information for
     * @param coreContract Contract address of the core contract
     * @return isConfigured true only if token price has been configured on
     * this minter and an ERC20 token has been configured
     * @return tokenPriceInWei current price of token on this minter - invalid
     * if price has not yet been configured. Note that "in wei" is a misnomer
     * for ERC20 tokens, but is used here for ABI consistency with the ETH
     * minters. The value returned represents the price per token in base units.
     * For example, if the ERC20 token has 6 decimals, an input value of
     * `1_000_000` would represent a price of `1.000000` tokens.
     * @return currencySymbol currency symbol for purchases of project on this
     * minter. "UNCONFIG" if not yet configured. Note that currency symbol is
     * defined by the artist, and is not necessarily the same as the ERC20
     * token symbol on-chain.
     * @return currencyAddress currency address for purchases of project on
     * this minter. Null address if not yet configured.
     */
    function getPriceInfo(
        uint256 projectId,
        address coreContract
    )
        external
        view
        returns (
            bool isConfigured,
            uint256 tokenPriceInWei,
            string memory currencySymbol,
            address currencyAddress
        )
    {
        SetPriceLib.SetPriceProjectConfig
            storage setPriceProjectConfig_ = SetPriceLib
                .getSetPriceProjectConfig({
                    projectId: projectId,
                    coreContract: coreContract
                });
        tokenPriceInWei = setPriceProjectConfig_.pricePerToken;
        // get currency info from SplitFundsLib
        (currencyAddress, currencySymbol) = SplitFundsLib.getCurrencyInfoERC20({
            projectId: projectId,
            coreContract: coreContract
        });
        // report if price and ERC20 token are configured
        // @dev currencyAddress is non-zero if an ERC20 token is configured
        isConfigured =
            setPriceProjectConfig_.priceIsConfigured &&
            currencyAddress != address(0);
    }

    /**
     * Gets the current polyptych panel ID for the given project.
     * @param projectId Project ID to be queried
     * @param coreContract Contract address of the core contract
     * @return uint256 representing the current polyptych panel ID for the
     * given project
     */
    function getCurrentPolyptychPanelId(
        uint256 projectId,
        address coreContract
    ) external view returns (uint256) {
        return
            PolyptychLib.getPolyptychPanelId({
                projectId: projectId,
                coreContract: coreContract
            });
    }

    /**
     * Gets if the hash seed for the given project has been used on a given
     * polyptych panel id. The current polyptych panel ID for a given project
     * can be queried via the view function `getCurrentPolyptychPanelId`.
     * @param projectId Project ID to be queried
     * @param coreContract Contract address of the core contract
     * @param panelId Panel ID to be queried
     * @param hashSeed Hash seed to be queried
     * @return bool representing if the hash seed has been used on the given
     * polyptych panel ID
     */
    function getPolyptychPanelHashSeedIsMinted(
        uint256 projectId,
        address coreContract,
        uint256 panelId,
        bytes12 hashSeed
    ) external view returns (bool) {
        return
            PolyptychLib.getPolyptychPanelHashSeedIsMinted({
                projectId: projectId,
                coreContract: coreContract,
                panelId: panelId,
                hashSeed: hashSeed
            });
    }

    /**
     * @notice Syncs local maximum invocations of project `projectId` based on
     * the value currently defined in the core contract.
     * @param projectId Project ID to set the maximum invocations for.
     * @param coreContract Core contract address for the given project.
     * @dev this enables gas reduction after maxInvocations have been reached -
     * core contracts shall still enforce a maxInvocation check during mint.
     */
    function syncProjectMaxInvocationsToCore(
        uint256 projectId,
        address coreContract
    ) public {
        AuthLib.onlyArtist({
            projectId: projectId,
            coreContract: coreContract,
            sender: msg.sender
        });

        MaxInvocationsLib.syncProjectMaxInvocationsToCore({
            projectId: projectId,
            coreContract: coreContract
        });
    }

    /**
     * @notice Purchases a token from project `projectId` on core contract
     * `coreContract` using an owned NFT at address `ownedNFTAddress` and
     * token ID `ownedNFTTokenId` as the parent token.
     * Sets the token's owner to `to`.
     * Parent token must be owned by `msg.sender`, or `vault` if `msg.sender`
     * is a valid delegate for `vault`.
     * @param to Address to be the new token's owner.
     * @param projectId Project ID to mint a token on.
     * @param coreContract Core contract address for the given project.
     * @param maxPricePerToken Maximum price of token being allowed by the
     * purchaser, in base units. For example, if the ERC20 token has 6
     * decimals, an input value of `1_000_000` would represent a maximum price
     * of `1.000000` tokens.
     * @param currencyAddress Currency address of token.
     * @param ownedNFTAddress ERC-721 NFT holding the project token owned by
     * msg.sender or `vault` being used as the parent token.
     * @param ownedNFTTokenId ERC-721 NFT token ID owned by msg.sender or
     * `vault` being used as the parent token.
     * @return tokenId Token ID of minted token
     */
    function purchaseTo(
        address to,
        uint256 projectId,
        address coreContract,
        uint256 maxPricePerToken,
        address currencyAddress,
        address ownedNFTAddress,
        uint256 ownedNFTTokenId,
        address vault
    ) public nonReentrant returns (uint256 tokenId) {
        // CHECKS
        // pre-mint MaxInvocationsLib checks
        // Note that `maxHasBeenInvoked` is only checked here to reduce gas
        // consumption after a project has been fully minted.
        // `maxInvocationsProjectConfig.maxHasBeenInvoked` is locally cached to reduce
        // gas consumption, but if not in sync with the core contract's value,
        // the core contract also enforces its own max invocation check during
        // minting.
        MaxInvocationsLib.preMintChecks({
            projectId: projectId,
            coreContract: coreContract
        });

        // pre-mint checks for set price lib, and get price per token
        // @dev price per token is loaded into memory here for gas efficiency
        uint256 pricePerToken = SetPriceLib.preMintChecksAndGetPrice({
            projectId: projectId,
            coreContract: coreContract
        });

        // @dev block scope to avoid stack too deep error
        {
            // get the currency address configured on the project
            // @dev revert occurs during payment split if ERC20 token is not
            // configured (i.e. address(0)), so check is not performed here
            (address configuredCurrencyAddress, ) = SplitFundsLib
                .getCurrencyInfoERC20({
                    projectId: projectId,
                    coreContract: coreContract
                });
            // validate that the currency address and symbols matches the project configured currency
            require(
                currencyAddress == configuredCurrencyAddress,
                "Currency addresses must match"
            );
        }

        // validate that the specified maximum price is greater than or equal to the price per token
        require(
            maxPricePerToken >= pricePerToken,
            "Only max price gte token price"
        );

        // require token used to claim to be in set of allowlisted NFTs
        require(
            TokenHolderLib.isAllowlistedNFT({
                projectId: projectId,
                coreContract: coreContract,
                ownedNFTAddress: ownedNFTAddress,
                ownedNFTTokenId: ownedNFTTokenId
            }),
            "Only allowlisted NFTs"
        );

        // NOTE: delegate-vault handling **begins here**.

        // handle that the vault may be either the `msg.sender` in the case
        // that there is not a true vault, or may be `vault` if one is
        // provided explicitly (and it is valid).
        address vault_ = msg.sender;
        if (vault != address(0)) {
            // If a vault is provided, it must be valid, otherwise throw rather
            // than optimistically-minting with original `msg.sender`.
            // Note, we do not check `checkDelegateForAll` or `checkDelegateForContract` as well,
            // as they are known to be implicitly checked by calling `checkDelegateForToken`.
            bool isValidVault = _delegationRegistryContract
                .checkDelegateForToken({
                    delegate: msg.sender,
                    vault: vault,
                    contract_: coreContract,
                    tokenId: ownedNFTTokenId
                });
            require(isValidVault, "Invalid delegate-vault pairing");
            vault_ = vault;
        }

        // we need the new token ID in advance of the randomizer setting a token hash
        IGenArt721CoreContractV3_Base genArtCoreContract = IGenArt721CoreContractV3_Base(
                coreContract
            );
        (uint256 invocations, , , , , ) = genArtCoreContract.projectStateData(
            projectId
        );

        // EFFECTS

        // we need to store the new token ID before it is minted so the randomizer can query it
        // @dev block scope to avoid stack too deep error
        {
            bytes12 targetHashSeed = PolyptychLib.getTokenHashSeed({
                coreContract: ownedNFTAddress,
                tokenId: ownedNFTTokenId
            });

            PolyptychLib.validatePolyptychEffects({
                projectId: projectId,
                coreContract: coreContract,
                tokenHashSeed: targetHashSeed
            });

            // @dev block scope to avoid stack too deep error
            {
                uint256 newTokenId = (projectId * ONE_MILLION) + invocations;
                PolyptychLib.setPolyptychHashSeed({
                    coreContract: coreContract,
                    tokenId: newTokenId, // new token ID
                    hashSeed: targetHashSeed
                });
            }

            // once mint() is called, the polyptych randomizer will either:
            // 1) assign a random token hash
            // 2) if configured, obtain the token hash from the `polyptychSeedHashes` mapping
            tokenId = _minterFilter.mint_joo({
                to: to,
                projectId: projectId,
                coreContract: coreContract,
                sender: vault_
            });

            // NOTE: delegate-vault handling **ends here**.

            // redundant check against reentrancy
            PolyptychLib.validateAssignedHashSeed({
                coreContract: coreContract,
                tokenId: tokenId,
                targetHashSeed: targetHashSeed
            });
        }

        MaxInvocationsLib.validateMintEffectsInvocations({
            tokenId: tokenId,
            coreContract: coreContract
        });

        // INTERACTIONS
        // @dev block scope to avoid stack too deep error
        {
            // require proper ownership of NFT used to redeem
            /**
             * @dev Considered an interaction because calling ownerOf on an NFT
             * contract. Plan is to only integrate with AB/PBAB NFTs on the minter, but
             * in case other NFTs are registered, better to check here. Also,
             * function is non-reentrant, so this is extra cautious.
             */
            // @dev if the artist is the sender, then the NFT must be owned by the
            // recipient, otherwise the NFT must be owned by the vault_
            address _artist = genArtCoreContract.projectIdToArtistAddress(
                projectId
            );
            address targetOwner = (msg.sender == _artist) ? to : vault_;
            TokenHolderLib.validateNFTOwnership({
                ownedNFTAddress: ownedNFTAddress,
                ownedNFTTokenId: ownedNFTTokenId,
                targetOwner: targetOwner
            });
        }

        // split funds
        // process payment in ERC20
        SplitFundsLib.splitFundsERC20({
            projectId: projectId,
            pricePerToken: pricePerToken,
            coreContract: coreContract
        });

        return tokenId;
    }
}

