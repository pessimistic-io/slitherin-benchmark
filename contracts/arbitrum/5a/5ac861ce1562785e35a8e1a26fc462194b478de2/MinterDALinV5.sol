// SPDX-License-Identifier: LGPL-3.0-only
// Created By: Art Blocks Inc.

// @dev fixed to specific solidity version for clarity and for more clear
// source code verification purposes.
pragma solidity 0.8.19;

import {ISharedMinterSimplePurchaseV0} from "./ISharedMinterSimplePurchaseV0.sol";
import {ISharedMinterDAV0} from "./ISharedMinterDAV0.sol";
import {ISharedMinterV0} from "./ISharedMinterV0.sol";
import {ISharedMinterDALinV0} from "./ISharedMinterDALinV0.sol";
import {IMinterFilterV1} from "./IMinterFilterV1.sol";

import {SplitFundsLib} from "./SplitFundsLib.sol";
import {MaxInvocationsLib} from "./MaxInvocationsLib.sol";
import {DALinLib} from "./DALinLib.sol";
import {AuthLib} from "./AuthLib.sol";

import {SafeCast} from "./SafeCast.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

/**
 * @title Shared, filtered Minter contract that allows tokens to be minted with
 * ETH. Pricing is achieved using an automated, linear Dutch-auction mechanism.
 * This is designed to be used with GenArt721CoreContractV3 flagship or
 * engine contracts.
 * @author Art Blocks Inc.
 * @notice Privileged Roles and Ownership:
 * This contract is designed to be managed, with limited powers.
 * Privileged roles and abilities are controlled by the project's artist, which
 * can be modified by the core contract's Admin ACL contract. Both of these
 * roles hold extensive power and can modify minter details.
 * Care must be taken to ensure that the admin ACL contract and artist
 * addresses are secure behind a multi-sig or other access control mechanism.
 * ----------------------------------------------------------------------------
 * The following functions are restricted to the minter filter's Admin ACL
 * contract:
 * - setMinimumPriceDecayHalfLifeSeconds
 * ----------------------------------------------------------------------------
 * The following functions are restricted to the core contract's Admin ACL
 * contract:
 * - resetAuctionDetails (note: this will prevent minting until a new auction
 *   is created)
 * ----------------------------------------------------------------------------
 * The following functions are restricted to a project's artist:
 * - setAuctionDetails (note: this may only be called when there is no active
 *   auction)
 * - syncProjectMaxInvocationsToCore
 * - manuallyLimitProjectMaxInvocations
 * ----------------------------------------------------------------------------
 * Additional admin and artist privileged roles may be described on other
 * contracts that this minter integrates with.
 * ----------------------------------------------------------------------------
 * @notice Caution: While Engine projects must be registered on the Art Blocks
 * Core Registry to assign this minter, this minter does not enforce that a
 * project is registered when configured or queried. This is primarily for gas
 * optimization purposes. It is, therefore, possible that fake projects may be
 * configured on this minter, but they will not be able to mint tokens due to
 * checks performed by this minter's Minter Filter.
 *
 *  @dev Note that while this minter makes use of `block.timestamp` and it is
 * technically possible that this value is manipulated by block producers, such
 * manipulation will not have material impact on the price values of this minter
 * given the business practices for how pricing is congfigured for this minter
 * and that variations on the order of less than a minute should not
 * meaningfully impact price given the minimum allowable price decay rate that
 * this minter intends to support.
 */
contract MinterDALinV5 is
    ReentrancyGuard,
    ISharedMinterSimplePurchaseV0,
    ISharedMinterV0,
    ISharedMinterDAV0,
    ISharedMinterDALinV0
{
    using SafeCast for uint256;
    /// Minter filter address this minter interacts with
    address public immutable minterFilterAddress;

    /// Minter filter this minter may interact with.
    IMinterFilterV1 private immutable _minterFilter;

    /// minterType for this minter
    string public constant minterType = "MinterDALinV5";

    /// minter version for this minter
    string public constant minterVersion = "v5.0.0";

    /// Minimum auction length in seconds
    uint256 public minimumAuctionLengthSeconds = 600; // 10 minutes

    /**
     * @notice Initializes contract to be a Filtered Minter for
     * `minterFilter` minter filter.
     * @param minterFilter Minter filter for which this will be a
     * filtered minter.
     */
    constructor(address minterFilter) ReentrancyGuard() {
        minterFilterAddress = minterFilter;
        _minterFilter = IMinterFilterV1(minterFilter);
        emit DALinLib.AuctionMinimumLengthSecondsUpdated(
            minimumAuctionLengthSeconds
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
     * @notice Sets auction details for project `projectId`.
     * @dev Note that allowing the artist to set auction details after reaching
     * max invocations effectively grants the artist the ability to set a new
     * auction at any point, since minter-local max invocations can be set by
     * the artist.
     * @param projectId Project ID to set auction details for.
     * @param coreContract Core contract address for the given project.
     * @param auctionTimestampStart Timestamp at which to start the auction.
     * @param auctionTimestampEnd Timestamp at which to end the auction.
     * @param startPrice Price at which to start the auction, in Wei.
     * @param basePrice Resting price of the auction, in Wei.
     * @dev Note that it is intentionally supported here that the configured
     * price may be explicitly set to `0`.
     */
    function setAuctionDetails(
        uint256 projectId,
        address coreContract,
        uint40 auctionTimestampStart,
        uint40 auctionTimestampEnd,
        uint256 startPrice,
        uint256 basePrice
    ) external {
        AuthLib.onlyArtist({
            projectId: projectId,
            coreContract: coreContract,
            sender: msg.sender
        });
        // CHECKS
        require(
            auctionTimestampEnd >=
                auctionTimestampStart + minimumAuctionLengthSeconds,
            "Auction length must be at least minimumAuctionLengthSeconds"
        );

        // EFFECTS
        bool maxHasBeenInvoked = MaxInvocationsLib.getMaxHasBeenInvoked({
            projectId: projectId,
            coreContract: coreContract
        });
        DALinLib.setAuctionDetailsLin({
            projectId: projectId,
            coreContract: coreContract,
            auctionTimestampStart: auctionTimestampStart,
            auctionTimestampEnd: auctionTimestampEnd,
            startPrice: startPrice.toUint88(),
            basePrice: basePrice.toUint88(),
            allowReconfigureAfterStart: maxHasBeenInvoked
        });

        // sync local max invocations if not initially populated
        // @dev if local max invocations and maxHasBeenInvoked are both
        // initial values, we know they have not been populated.
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
     * @notice Sets minimum auction length to `minimumAuctionLengthSeconds`
     * for all projects.
     * @param minimumAuctionLengthSeconds_ Minimum auction length in seconds.
     */
    function setMinimumAuctionLengthSeconds(
        uint256 minimumAuctionLengthSeconds_
    ) external {
        AuthLib.onlyMinterFilterAdminACL({
            minterFilterAddress: minterFilterAddress,
            sender: msg.sender,
            contract_: address(this),
            selector: this.setMinimumAuctionLengthSeconds.selector
        });
        minimumAuctionLengthSeconds = minimumAuctionLengthSeconds_;
        emit DALinLib.AuctionMinimumLengthSecondsUpdated(
            minimumAuctionLengthSeconds_
        );
    }

    /**
     * @notice Resets auction details for project `projectId`, zero-ing out all
     * relevant auction fields. Not intended to be used in normal auction
     * operation, but rather only in case of the need to halt an auction.
     * @param projectId Project ID to set auction details for.
     * @param coreContract Core contract address for the given project.
     */
    function resetAuctionDetails(
        uint256 projectId,
        address coreContract
    ) external {
        AuthLib.onlyCoreAdminACL({
            coreContract: coreContract,
            sender: msg.sender,
            contract_: address(this),
            selector: this.resetAuctionDetails.selector
        });

        DALinLib.resetAuctionDetails({
            projectId: projectId,
            coreContract: coreContract
        });
    }

    /**
     * @notice Purchases a token from project `projectId`.
     * Note: Collectors should not send excessive value with their purchase
     * transaction, because the artist has the ability to change the auction
     * details at any time, including the price.
     * @param projectId Project ID to mint a token on.
     * @param coreContract Core contract address for the given project.
     * @return tokenId Token ID of minted token
     */
    function purchase(
        uint256 projectId,
        address coreContract
    ) external payable returns (uint256 tokenId) {
        tokenId = purchaseTo({
            to: msg.sender,
            projectId: projectId,
            coreContract: coreContract
        });

        return tokenId;
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
     * @notice Retrieves the auction parameters for a specific project.
     * @param projectId The unique identifier for the project.
     * @param coreContract The address of the core contract for the project.
     * @return timestampStart The start timestamp for the auction.
     * @return timestampEnd The end timestamp for the auction.
     * @return startPrice The starting price of the auction.
     * @return basePrice The base price of the auction.
     */
    function projectAuctionParameters(
        uint256 projectId,
        address coreContract
    )
        external
        view
        returns (
            uint40 timestampStart,
            uint40 timestampEnd,
            uint256 startPrice,
            uint256 basePrice
        )
    {
        DALinLib.DAProjectConfig storage auctionProjectConfig = DALinLib
            .getDAProjectConfig(projectId, coreContract);
        timestampStart = auctionProjectConfig.timestampStart;
        timestampEnd = auctionProjectConfig.timestampEnd;
        startPrice = auctionProjectConfig.startPrice;
        basePrice = auctionProjectConfig.basePrice;
    }

    /**
     * @notice Checks if the specified `coreContract` is a valid engine contract.
     * @dev This function retrieves the cached value of `coreContract` from
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
     * @notice Gets if price of token is configured, price of minting a
     * token on project `projectId`, and currency symbol and address to be
     * used as payment. Supersedes any core contract price information.
     * @param projectId Project ID to get price information for
     * @param coreContract Contract address of the core contract
     * @return isConfigured true only if token price has been configured on
     * this minter
     * @return tokenPriceInWei current price of token on this minter - invalid
     * if price has not yet been configured
     * @return currencySymbol currency symbol for purchases of project on this
     * minter. This minter always returns "ETH"
     * @return currencyAddress currency address for purchases of project on
     * this minter. This minter always returns null address, reserved for ether
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
        DALinLib.DAProjectConfig storage auctionProjectConfig = DALinLib
            .getDAProjectConfig({
                projectId: projectId,
                coreContract: coreContract
            });
        isConfigured = (auctionProjectConfig.startPrice > 0);
        if (!isConfigured) {
            // In the case of unconfigured auction, return price of zero when
            // getPriceLin would otherwise revert
            tokenPriceInWei = 0;
        } else if (block.timestamp <= auctionProjectConfig.timestampStart) {
            // Provide a reasonable value for `tokenPriceInWei` when
            // getPriceLin would otherwise revert, using the starting price
            // before auction starts.
            tokenPriceInWei = auctionProjectConfig.startPrice;
        } else {
            tokenPriceInWei = DALinLib.getPriceLin({
                projectId: projectId,
                coreContract: coreContract
            });
        }
        currencySymbol = "ETH";
        currencyAddress = address(0);
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
     * @notice Purchases a token from project `projectId` and sets
     * the token's owner to `to`.
     * Note: Collectors should not send excessive value with their purchase
     * transaction, because the artist has the ability to change the auction
     * details at any time, including the price.
     * @param to Address to be the new token's owner.
     * @param projectId Project ID to mint a token on.
     * @param coreContract Core contract address for the given project.
     * @return tokenId Token ID of minted token
     */
    function purchaseTo(
        address to,
        uint256 projectId,
        address coreContract
    ) public payable nonReentrant returns (uint256 tokenId) {
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

        // getPriceLin reverts if auction is unconfigured or has not started
        uint256 pricePerTokenInWei = DALinLib.getPriceLin({
            projectId: projectId,
            coreContract: coreContract
        });
        require(msg.value >= pricePerTokenInWei, "Min value to mint req.");

        // EFFECTS
        tokenId = _minterFilter.mint_joo({
            to: to,
            projectId: projectId,
            coreContract: coreContract,
            sender: msg.sender
        });

        MaxInvocationsLib.validateMintEffectsInvocations({
            tokenId: tokenId,
            coreContract: coreContract
        });

        // INTERACTIONS
        SplitFundsLib.splitFundsETHRefundSender({
            projectId: projectId,
            pricePerTokenInWei: pricePerTokenInWei,
            coreContract: coreContract
        });

        return tokenId;
    }
}

