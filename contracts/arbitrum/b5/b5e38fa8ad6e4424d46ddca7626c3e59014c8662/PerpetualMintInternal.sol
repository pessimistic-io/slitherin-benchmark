// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { VRFCoordinatorV2Interface } from "./VRFCoordinatorV2Interface.sol";
import { VRFConsumerBaseV2 } from "./VRFConsumerBaseV2.sol";
import { OwnableInternal } from "./OwnableInternal.sol";
import { EnumerableSet } from "./EnumerableSet.sol";
import { ERC1155BaseInternal } from "./ERC1155BaseInternal.sol";
import { AddressUtils } from "./AddressUtils.sol";

import { ISupraRouterContract } from "./ISupraRouterContract.sol";
import { ERC1155MetadataExtensionInternal } from "./ERC1155MetadataExtensionInternal.sol";
import { IPerpetualMintInternal } from "./IPerpetualMintInternal.sol";
import { CollectionData, MintOutcome, MintResultData, MintTokenTiersData, PerpetualMintStorage as Storage, RequestData, TiersData, VRFConfig } from "./Storage.sol";
import { IToken } from "./IToken.sol";
import { GuardsInternal } from "./GuardsInternal.sol";

/// @title PerpetualMintInternal
/// @dev defines modularly all logic for the PerpetualMint mechanism in internal functions
abstract contract PerpetualMintInternal is
    ERC1155BaseInternal,
    ERC1155MetadataExtensionInternal,
    GuardsInternal,
    OwnableInternal,
    IPerpetualMintInternal,
    VRFConsumerBaseV2
{
    using AddressUtils for address payable;
    using EnumerableSet for EnumerableSet.UintSet;

    /// @dev denominator used in percentage calculations
    uint32 private constant BASIS = 1000000000;

    /// @dev default mint price for a collection
    uint64 internal constant DEFAULT_COLLECTION_MINT_PRICE = 0.01 ether;

    /// @dev default risk for a collection
    uint32 internal constant DEFAULT_COLLECTION_RISK = 1000000; // 0.1%

    // Starting default conversion ratio: 1 ETH = 1,000,000 $MINT
    uint32 internal constant DEFAULT_ETH_TO_MINT_RATIO = 1000000;

    /// @dev address of the configured VRF
    address private immutable VRF;

    constructor(address vrfCoordinator) VRFConsumerBaseV2(vrfCoordinator) {
        VRF = vrfCoordinator;
    }

    /// @notice returns the current accrued consolation fees
    /// @return accruedFees the current amount of accrued consolation fees
    function _accruedConsolationFees()
        internal
        view
        returns (uint256 accruedFees)
    {
        accruedFees = Storage.layout().consolationFees;
    }

    /// @notice returns the current accrued mint earnings across all collections
    /// @return accruedMintEarnings the current amount of accrued mint earnings across all collections
    function _accruedMintEarnings()
        internal
        view
        returns (uint256 accruedMintEarnings)
    {
        accruedMintEarnings = Storage.layout().mintEarnings;
    }

    /// @notice returns the current accrued protocol fees
    /// @return accruedFees the current amount of accrued protocol fees
    function _accruedProtocolFees()
        internal
        view
        returns (uint256 accruedFees)
    {
        accruedFees = Storage.layout().protocolFees;
    }

    /// @notice Attempts a batch mint for the msg.sender for $MINT using ETH as payment.
    /// @param minter address of minter
    /// @param numberOfMints number of mints to attempt
    function _attemptBatchMintForMintWithEth(
        address minter,
        uint32 numberOfMints
    ) internal {
        Storage.Layout storage l = Storage.layout();

        // for now, mints for $MINT are treated as address(0) collections
        address collection = address(0);

        CollectionData storage collectionData = l.collections[collection];

        _attemptBatchMintForMintWithEth_sharedLogic(
            l,
            msg.value,
            _collectionMintPrice(collectionData),
            numberOfMints
        );

        // if the number of words requested is greater than the max allowed by the VRF coordinator,
        // the request for random words will fail (max random words is currently 500 per request).
        uint32 numWords = numberOfMints * 1; // 1 words per mint for $MINT, current max of 500 mints per tx

        _requestRandomWords(l, collectionData, minter, collection, numWords);
    }

    /// @notice Attempts a Base-specific batch mint for the msg.sender for $MINT using ETH as payment.
    /// @param minter address of minter
    /// @param numberOfMints number of mints to attempt
    function _attemptBatchMintForMintWithEthBase(
        address minter,
        uint8 numberOfMints
    ) internal {
        Storage.Layout storage l = Storage.layout();

        // for now, mints for $MINT are treated as address(0) collections
        address collection = address(0);

        CollectionData storage collectionData = l.collections[collection];

        _attemptBatchMintForMintWithEth_sharedLogic(
            l,
            msg.value,
            _collectionMintPrice(collectionData),
            numberOfMints
        );

        // if the number of words requested is greater than uint8, the function call will revert.
        // the current max allowed by Supra VRF is 255 per request.
        uint8 numWords = numberOfMints * 1; // 1 words per mint for $MINT, current max of 255 mints per tx

        _requestRandomWordsBase(
            l,
            collectionData,
            minter,
            collection,
            numWords
        );
    }

    function _attemptBatchMintForMintWithEth_sharedLogic(
        Storage.Layout storage l,
        uint256 msgValue,
        uint256 mintForMintPrice,
        uint32 numberOfMints
    ) private {
        if (numberOfMints == 0) {
            revert InvalidNumberOfMints();
        }

        if (msgValue != mintForMintPrice * numberOfMints) {
            revert IncorrectETHReceived();
        }

        // calculate the mint for $MINT consolation fee
        uint256 mintTokenConsolationFee = (msgValue *
            l.mintTokenConsolationFeeBP) / BASIS;

        // update the accrued consolation fees
        l.consolationFees += mintTokenConsolationFee;

        // update the accrued protocol fees
        l.protocolFees += msgValue - mintTokenConsolationFee;
    }

    /// @notice Attempts a batch mint for the msg.sender for $MINT using $MINT tokens as payment.
    /// @param minter address of minter
    /// @param numberOfMints number of mints to attempt
    function _attemptBatchMintForMintWithMint(
        address minter,
        uint32 numberOfMints
    ) internal {
        Storage.Layout storage l = Storage.layout();

        // for now, mints for $MINT are treated as address(0) collections
        address collection = address(0);

        CollectionData storage collectionData = l.collections[collection];

        uint256 collectionMintPrice = _collectionMintPrice(collectionData);

        uint256 ethRequired = collectionMintPrice * numberOfMints;

        uint256 ethToMintRatio = _ethToMintRatio(l);

        _attemptBatchMintForMintWithMint_sharedLogic(
            l,
            ethRequired,
            numberOfMints,
            ethToMintRatio,
            minter
        );

        // if the number of words requested is greater than the max allowed by the VRF coordinator,
        // the request for random words will fail (max random words is currently 500 per request).
        uint32 numWords = numberOfMints * 1; // 1 words per mint for $MINT, current max of 500 mints per tx

        _requestRandomWords(l, collectionData, minter, collection, numWords);
    }

    /// @notice Attempts a Base-specific batch mint for the msg.sender for $MINT using $MINT tokens as payment.
    /// @param minter address of minter
    /// @param numberOfMints number of mints to attempt
    function _attemptBatchMintForMintWithMintBase(
        address minter,
        uint8 numberOfMints
    ) internal {
        Storage.Layout storage l = Storage.layout();

        // for now, mints for $MINT are treated as address(0) collections
        address collection = address(0);

        CollectionData storage collectionData = l.collections[collection];

        uint256 collectionMintPrice = _collectionMintPrice(collectionData);

        uint256 ethRequired = collectionMintPrice * numberOfMints;

        uint256 ethToMintRatio = _ethToMintRatio(l);

        _attemptBatchMintForMintWithMint_sharedLogic(
            l,
            ethRequired,
            numberOfMints,
            ethToMintRatio,
            minter
        );

        // if the number of words requested is greater than uint8, the function call will revert.
        // the current max allowed by Supra VRF is 255 per request.
        uint8 numWords = numberOfMints * 1; // 1 words per mint for $MINT, current max of 255 mints per tx

        _requestRandomWordsBase(
            l,
            collectionData,
            minter,
            collection,
            numWords
        );
    }

    function _attemptBatchMintForMintWithMint_sharedLogic(
        Storage.Layout storage l,
        uint256 ethRequired,
        uint32 numberOfMints,
        uint256 ethToMintRatio,
        address minter
    ) private {
        if (numberOfMints == 0) {
            revert InvalidNumberOfMints();
        }

        if (ethRequired > l.consolationFees) {
            revert InsufficientConsolationFees();
        }

        // calculate amount of $MINT required
        uint256 mintRequired = ethRequired * ethToMintRatio;

        IToken(l.mintToken).burn(minter, mintRequired);

        // calculate the mint for $MINT consolation fee
        uint256 mintTokenConsolationFee = (ethRequired *
            l.mintTokenConsolationFeeBP) / BASIS;

        // Calculate the net mint fee
        uint256 netMintFee = ethRequired - mintTokenConsolationFee;

        // Update the accrued consolation fees
        l.consolationFees -= netMintFee;

        // Update the accrued protocol fees
        l.protocolFees += netMintFee;
    }

    /// @notice Attempts a batch mint for the msg.sender for a single collection using ETH as payment.
    /// @param minter address of minter
    /// @param collection address of collection for mint attempts
    /// @param numberOfMints number of mints to attempt
    function _attemptBatchMintWithEth(
        address minter,
        address collection,
        uint32 numberOfMints
    ) internal {
        Storage.Layout storage l = Storage.layout();

        CollectionData storage collectionData = l.collections[collection];

        _attemptBatchMintWithEth_sharedLogic(
            l,
            collectionData,
            msg.value,
            collection,
            numberOfMints
        );

        // if the number of words requested is greater than the max allowed by the VRF coordinator,
        // the request for random words will fail (max random words is currently 500 per request).
        uint32 numWords = numberOfMints * 2; // 2 words per mint, current max of 250 mints per tx

        _requestRandomWords(l, collectionData, minter, collection, numWords);
    }

    /// @notice Attempts a Base-specific batch mint for the msg.sender for a single collection using ETH as payment.
    /// @param minter address of minter
    /// @param collection address of collection for mint attempts
    /// @param numberOfMints number of mints to attempt
    function _attemptBatchMintWithEthBase(
        address minter,
        address collection,
        uint8 numberOfMints
    ) internal {
        Storage.Layout storage l = Storage.layout();

        CollectionData storage collectionData = l.collections[collection];

        _attemptBatchMintWithEth_sharedLogic(
            l,
            collectionData,
            msg.value,
            collection,
            numberOfMints
        );

        // if the number of words requested is greater than uint8, the function call will revert.
        // the current max allowed by Supra VRF is 255 per request.
        uint8 numWords = numberOfMints * 2; // 2 words per mint, current max of 127 mints per tx

        _requestRandomWordsBase(
            l,
            collectionData,
            minter,
            collection,
            numWords
        );
    }

    function _attemptBatchMintWithEth_sharedLogic(
        Storage.Layout storage l,
        CollectionData storage collectionData,
        uint256 msgValue,
        address collection,
        uint32 numberOfMints
    ) private {
        if (collection == address(0)) {
            // throw if collection is $MINT
            revert InvalidCollectionAddress();
        }

        if (numberOfMints == 0) {
            revert InvalidNumberOfMints();
        }

        uint256 collectionMintPrice = _collectionMintPrice(collectionData);

        if (msgValue != collectionMintPrice * numberOfMints) {
            revert IncorrectETHReceived();
        }

        // calculate the mint for collection consolation fee
        uint256 collectionConsolationFee = (msgValue *
            l.collectionConsolationFeeBP) / BASIS;

        // apply the collection-specific mint fee ratio
        uint256 additionalDepositorFee = (collectionConsolationFee *
            collectionData.mintFeeDistributionRatioBP) / BASIS;

        // calculate the protocol mint fee
        uint256 mintFee = (msgValue * l.mintFeeBP) / BASIS;

        // update the accrued consolation fees
        l.consolationFees += collectionConsolationFee - additionalDepositorFee;

        // update the accrued depositor mint earnings
        l.mintEarnings +=
            msgValue -
            collectionConsolationFee -
            mintFee +
            additionalDepositorFee;

        // update the accrued protocol fees
        l.protocolFees += mintFee;
    }

    /// @notice Attempts a batch mint for the msg.sender for a single collection using $MINT tokens as payment.
    /// @param minter address of minter
    /// @param collection address of collection for mint attempts
    /// @param numberOfMints number of mints to attempt
    function _attemptBatchMintWithMint(
        address minter,
        address collection,
        uint32 numberOfMints
    ) internal {
        Storage.Layout storage l = Storage.layout();

        CollectionData storage collectionData = l.collections[collection];

        _attemptBatchMintWithMint_sharedLogic(
            l,
            collectionData,
            minter,
            collection,
            numberOfMints
        );

        // if the number of words requested is greater than the max allowed by the VRF coordinator,
        // the request for random words will fail (max random words is currently 500 per request).
        uint32 numWords = numberOfMints * 2; // 2 words per mint, current max of 250 mints per tx

        _requestRandomWords(l, collectionData, minter, collection, numWords);
    }

    /// @notice Attempts a Base-specific batch mint for the msg.sender for a single collection using $MINT tokens as payment.
    /// @param minter address of minter
    /// @param collection address of collection for mint attempts
    /// @param numberOfMints number of mints to attempt
    function _attemptBatchMintWithMintBase(
        address minter,
        address collection,
        uint8 numberOfMints
    ) internal {
        Storage.Layout storage l = Storage.layout();

        CollectionData storage collectionData = l.collections[collection];

        _attemptBatchMintWithMint_sharedLogic(
            l,
            collectionData,
            minter,
            collection,
            numberOfMints
        );

        // if the number of words requested is greater than uint8, the function call will revert.
        // the current max allowed by Supra VRF is 255 per request.
        uint8 numWords = numberOfMints * 2; // 2 words per mint, current max of 127 mints per tx

        _requestRandomWordsBase(
            l,
            collectionData,
            minter,
            collection,
            numWords
        );
    }

    function _attemptBatchMintWithMint_sharedLogic(
        Storage.Layout storage l,
        CollectionData storage collectionData,
        address minter,
        address collection,
        uint32 numberOfMints
    ) private {
        if (collection == address(0)) {
            revert InvalidCollectionAddress();
        }

        if (numberOfMints == 0) {
            revert InvalidNumberOfMints();
        }

        uint256 collectionMintPrice = _collectionMintPrice(collectionData);

        uint256 ethRequired = collectionMintPrice * numberOfMints;

        if (ethRequired > l.consolationFees) {
            revert InsufficientConsolationFees();
        }

        uint256 ethToMintRatio = _ethToMintRatio(l);

        // calculate amount of $MINT required
        uint256 mintRequired = ethRequired * ethToMintRatio;

        IToken(l.mintToken).burn(minter, mintRequired);

        // calculate the mint for collection consolation fee
        uint256 collectionConsolationFee = (ethRequired *
            l.collectionConsolationFeeBP) / BASIS;

        // apply the collection-specific mint fee ratio
        uint256 additionalDepositorFee = (collectionConsolationFee *
            collectionData.mintFeeDistributionRatioBP) / BASIS;

        // calculate the protocol mint fee
        uint256 mintFee = (ethRequired * l.mintFeeBP) / BASIS;

        // calculate the net collection consolation fee
        // ETH required for mint taken from collectionConsolationFee
        uint256 netConsolationFee = ethRequired -
            collectionConsolationFee +
            additionalDepositorFee;

        // update the accrued consolation fees
        l.consolationFees -= netConsolationFee;

        // update the accrued depositor mint earnings
        l.mintEarnings += netConsolationFee - mintFee;

        // update the accrued protocol fees
        l.protocolFees += mintFee;
    }

    /// @notice returns the value of BASIS
    /// @return value BASIS value
    function _BASIS() internal pure returns (uint32 value) {
        value = BASIS;
    }

    /// @notice burns a receipt after a claim request is fulfilled
    /// @param tokenId id of receipt to burn
    function _burnReceipt(uint256 tokenId) internal {
        _burn(address(this), tokenId, 1);
    }

    /// @notice calculates the mint result of a given number of mint attempts for a given collection using given randomness
    /// @param collection address of collection for mint attempts
    /// @param numberOfMints number of mints to attempt
    /// @param randomness random value to use in calculation
    function _calculateMintResult(
        address collection,
        uint32 numberOfMints,
        uint256 randomness
    ) internal view returns (MintResultData memory result) {
        Storage.Layout storage l = Storage.layout();

        CollectionData storage collectionData = l.collections[collection];

        bool mintForMint = collection == address(0);

        uint32 numberOfWords = numberOfMints * (mintForMint ? 1 : 2);

        uint256[] memory randomWords = new uint256[](numberOfWords);

        for (uint256 i = 0; i < numberOfWords; ++i) {
            randomWords[i] = uint256(keccak256(abi.encode(randomness, i)));
        }

        if (mintForMint) {
            result = _calculateMintForMintResult_sharedLogic(
                l,
                numberOfMints,
                randomWords,
                collectionData
            );
        } else {
            result = _calculateMintForCollectionResult_sharedLogic(
                l,
                numberOfMints,
                randomWords,
                collectionData
            );
        }
    }

    /// @notice calculates the Base-specific mint result of a given number of mint attempts for a given collection using given signature as randomness
    /// @param collection address of collection for mint attempts
    /// @param numberOfMints number of mints to attempt
    /// @param signature signature value to use as randomness in calculation
    function _calculateMintResultBase(
        address collection,
        uint8 numberOfMints,
        uint256[2] calldata signature
    ) internal view returns (MintResultData memory result) {
        Storage.Layout storage l = Storage.layout();

        CollectionData storage collectionData = l.collections[collection];

        bool mintForMint = collection == address(0);

        uint8 numberOfWords = numberOfMints * (mintForMint ? 1 : 2);

        uint256[] memory randomWords = new uint256[](numberOfWords);

        for (uint256 i = 0; i < numberOfWords; ++i) {
            randomWords[i] = uint256(
                keccak256(abi.encodePacked(signature, i + 1))
            );
        }

        if (mintForMint) {
            result = _calculateMintForMintResult_sharedLogic(
                l,
                numberOfMints,
                randomWords,
                collectionData
            );
        } else {
            result = _calculateMintForCollectionResult_sharedLogic(
                l,
                numberOfMints,
                randomWords,
                collectionData
            );
        }
    }

    function _calculateMintForCollectionResult_sharedLogic(
        Storage.Layout storage l,
        uint32 numberOfMints,
        uint256[] memory randomWords,
        CollectionData storage collectionData
    ) private view returns (MintResultData memory result) {
        TiersData storage tiers = l.tiers;

        uint32 collectionRisk = _collectionRisk(collectionData);
        uint256 ethToMintRatio = _ethToMintRatio(l);

        result.mintOutcomes = new MintOutcome[](numberOfMints);

        for (uint256 i = 0; i < randomWords.length; i += 2) {
            MintOutcome memory outcome;

            uint256 firstNormalizedValue = _normalizeValue(
                randomWords[i],
                BASIS
            );

            uint256 secondNormalizedValue = _normalizeValue(
                randomWords[i + 1],
                BASIS
            );

            if (!(collectionRisk > firstNormalizedValue)) {
                uint256 mintAmount;
                uint256 cumulativeRisk;

                for (uint256 j = 0; j < tiers.tierRisks.length; ++j) {
                    cumulativeRisk += tiers.tierRisks[j];

                    if (cumulativeRisk > secondNormalizedValue) {
                        mintAmount =
                            (tiers.tierMultipliers[j] *
                                ethToMintRatio *
                                _collectionMintPrice(collectionData) *
                                _collectionMintMultiplier(collectionData)) /
                            (uint256(BASIS) * BASIS);

                        outcome.tierIndex = j;
                        outcome.tierMultiplier = tiers.tierMultipliers[j];
                        outcome.tierRisk = tiers.tierRisks[j];
                        outcome.mintAmount = mintAmount;

                        break;
                    }
                }

                result.totalMintAmount += mintAmount;
            } else {
                ++result.totalSuccessfulMints;
            }

            result.mintOutcomes[i / 2] = outcome;
        }
    }

    function _calculateMintForMintResult_sharedLogic(
        Storage.Layout storage l,
        uint32 numberOfMints,
        uint256[] memory randomWords,
        CollectionData storage collectionData
    ) private view returns (MintResultData memory result) {
        MintTokenTiersData storage mintTokenTiers = l.mintTokenTiers;

        uint256 ethToMintRatio = _ethToMintRatio(l);

        result.mintOutcomes = new MintOutcome[](numberOfMints);

        for (uint256 i = 0; i < randomWords.length; ++i) {
            MintOutcome memory outcome;

            uint256 normalizedValue = _normalizeValue(randomWords[i], BASIS);

            uint256 mintAmount;
            uint256 cumulativeRisk;

            for (uint256 j = 0; j < mintTokenTiers.tierRisks.length; ++j) {
                cumulativeRisk += mintTokenTiers.tierRisks[j];

                if (cumulativeRisk > normalizedValue) {
                    mintAmount =
                        (mintTokenTiers.tierMultipliers[j] *
                            ethToMintRatio *
                            _collectionMintPrice(collectionData) *
                            _collectionMintMultiplier(collectionData)) /
                        (uint256(BASIS) * BASIS);

                    outcome.tierIndex = j;
                    outcome.tierMultiplier = mintTokenTiers.tierMultipliers[j];
                    outcome.tierRisk = mintTokenTiers.tierRisks[j];
                    outcome.mintAmount = mintAmount;

                    break;
                }
            }

            result.totalMintAmount += mintAmount;

            result.mintOutcomes[i] = outcome;
        }
    }

    /// @notice Cancels a claim for a given claimer for given token ID
    /// @param claimer address of rejected claimer
    /// @param tokenId token ID of rejected claim
    function _cancelClaim(address claimer, uint256 tokenId) internal {
        _safeTransfer(address(this), address(this), claimer, tokenId, 1, "");

        emit ClaimCancelled(
            claimer,
            address(uint160(tokenId)) // decode tokenId to get collection address
        );
    }

    /// @notice claims all accrued mint earnings across collections
    /// @param recipient address of mint earnings recipient
    function _claimMintEarnings(address recipient) internal {
        Storage.Layout storage l = Storage.layout();

        uint256 mintEarnings = l.mintEarnings;
        l.mintEarnings = 0;

        payable(recipient).sendValue(mintEarnings);
    }

    /// @notice Initiates a claim for a prize for a given collection
    /// @param claimer address of claimer
    /// @param prizeRecipient address of intended prize recipient
    /// @param tokenId token ID of prize, which is the prize collection address encoded as uint256
    function _claimPrize(
        address claimer,
        address prizeRecipient,
        uint256 tokenId
    ) internal {
        _safeTransfer(msg.sender, claimer, address(this), tokenId, 1, "");

        emit PrizeClaimed(
            claimer,
            prizeRecipient,
            address(uint160(tokenId)) // decode tokenId to get collection address
        );
    }

    /// @notice claims all accrued protocol fees
    /// @param recipient address of protocol fees recipient
    function _claimProtocolFees(address recipient) internal {
        Storage.Layout storage l = Storage.layout();

        uint256 protocolFees = l.protocolFees;
        l.protocolFees = 0;

        payable(recipient).sendValue(protocolFees);
    }

    /// @notice Returns the current mint fee distribution ratio in basis points for a collection
    /// @param collection address of collection
    /// @return ratioBP current collection mint fee distribution ratio in basis points
    function _collectionMintFeeDistributionRatioBP(
        address collection
    ) internal view returns (uint32 ratioBP) {
        ratioBP = Storage
            .layout()
            .collections[collection]
            .mintFeeDistributionRatioBP;
    }

    /// @notice Returns the current collection multiplier for a given collection
    /// @param collectionData the CollectionData struct for a given collection
    /// @return multiplier current collection multiplier
    function _collectionMintMultiplier(
        CollectionData storage collectionData
    ) internal view returns (uint256 multiplier) {
        multiplier = collectionData.mintMultiplier;

        multiplier = multiplier == 0 ? BASIS : multiplier; // default multiplier is 1x
    }

    /// @notice Returns the current mint price for a given collection
    /// @param collectionData the CollectionData struct for a given collection
    /// @return mintPrice current collection mint price
    function _collectionMintPrice(
        CollectionData storage collectionData
    ) internal view returns (uint256 mintPrice) {
        mintPrice = collectionData.mintPrice;

        mintPrice = mintPrice == 0 ? DEFAULT_COLLECTION_MINT_PRICE : mintPrice;
    }

    /// @notice Returns the current collection-wide risk of a collection
    /// @param collectionData the CollectionData struct for a given collection
    /// @return risk value of collection-wide risk
    function _collectionRisk(
        CollectionData storage collectionData
    ) internal view returns (uint32 risk) {
        risk = collectionData.risk;

        risk = risk == 0 ? DEFAULT_COLLECTION_RISK : risk;
    }

    /// @notice Returns the current collection consolation fee in basis points
    /// @return collectionConsolationFeeBasisPoints mint for collection consolation fee in basis points
    function _collectionConsolationFeeBP()
        internal
        view
        returns (uint32 collectionConsolationFeeBasisPoints)
    {
        collectionConsolationFeeBasisPoints = Storage
            .layout()
            .collectionConsolationFeeBP;
    }

    /// @notice Returns the default mint price for a collection
    /// @return mintPrice default collection mint price
    function _defaultCollectionMintPrice()
        internal
        pure
        returns (uint256 mintPrice)
    {
        mintPrice = DEFAULT_COLLECTION_MINT_PRICE;
    }

    /// @notice Returns the default risk for a collection
    /// @return risk default collection risk
    function _defaultCollectionRisk() internal pure returns (uint32 risk) {
        risk = DEFAULT_COLLECTION_RISK;
    }

    /// @notice Returns the default ETH to $MINT ratio
    /// @return ratio default ETH to $MINT ratio
    function _defaultEthToMintRatio() internal pure returns (uint32 ratio) {
        ratio = DEFAULT_ETH_TO_MINT_RATIO;
    }

    /// @dev enforces that there are no pending mint requests for a collection
    /// @param collectionData the CollectionData struct for a given collection
    function _enforceNoPendingMints(
        CollectionData storage collectionData
    ) internal view {
        if (collectionData.pendingRequests.length() != 0) {
            revert PendingRequests();
        }
    }

    /// @notice Returns the current ETH to $MINT ratio
    /// @param l the PerpetualMint storage layout
    /// @return ratio current ETH to $MINT ratio
    function _ethToMintRatio(
        Storage.Layout storage l
    ) internal view returns (uint256 ratio) {
        ratio = l.ethToMintRatio;

        ratio = ratio == 0 ? DEFAULT_ETH_TO_MINT_RATIO : ratio;
    }

    /// @notice internal VRF callback
    /// @notice is executed by the configured VRF contract
    /// @param requestId id of VRF request
    /// @param randomWords random values return by the configured VRF contract
    function _fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal virtual {
        Storage.Layout storage l = Storage.layout();

        RequestData storage request = l.requests[requestId];

        address collection = request.collection;
        address minter = request.minter;

        CollectionData storage collectionData = l.collections[collection];

        // if the collection is address(0), the mint is for $MINT
        if (collection == address(0)) {
            _resolveMintsForMint(
                l.mintToken,
                _collectionMintMultiplier(collectionData),
                _collectionMintPrice(collectionData),
                l.mintTokenTiers,
                minter,
                randomWords,
                _ethToMintRatio(l)
            );
        } else {
            // if the collection is not address(0), the mint is for a collection

            _resolveMints(
                l.mintToken,
                _collectionMintMultiplier(collectionData),
                _collectionMintPrice(collectionData),
                _collectionRisk(collectionData),
                l.tiers,
                minter,
                collection,
                randomWords,
                _ethToMintRatio(l)
            );
        }

        collectionData.pendingRequests.remove(requestId);

        delete l.requests[requestId];
    }

    /// @notice funds the consolation fees pool with ETH
    function _fundConsolationFees() internal {
        Storage.layout().consolationFees += msg.value;

        emit ConsolationFeesFunded(msg.sender, msg.value);
    }

    /// @notice mints an amount of mintToken tokens to the mintToken contract in exchange for ETH
    /// @param amount amount of mintToken tokens to mint
    function _mintAirdrop(uint256 amount) internal {
        Storage.Layout storage l = Storage.layout();

        if (amount / _ethToMintRatio(l) != msg.value) {
            revert IncorrectETHReceived();
        }

        l.consolationFees += msg.value;

        IToken(l.mintToken).mintAirdrop(amount);
    }

    /// @notice Returns the current mint fee in basis points
    /// @return mintFeeBasisPoints mint fee in basis points
    function _mintFeeBP() internal view returns (uint32 mintFeeBasisPoints) {
        mintFeeBasisPoints = Storage.layout().mintFeeBP;
    }

    /// @notice Returns the address of the current $MINT token
    /// @return mintToken address of the current $MINT token
    function _mintToken() internal view returns (address mintToken) {
        mintToken = Storage.layout().mintToken;
    }

    /// @notice Returns the current $MINT consolation fee in basis points
    /// @return mintTokenConsolationFeeBasisPoints mint for $MINT consolation fee in basis points
    function _mintTokenConsolationFeeBP()
        internal
        view
        returns (uint32 mintTokenConsolationFeeBasisPoints)
    {
        mintTokenConsolationFeeBasisPoints = Storage
            .layout()
            .mintTokenConsolationFeeBP;
    }

    /// @notice Returns the current tier risks and multipliers for minting for $MINT
    function _mintTokenTiers()
        internal
        view
        returns (MintTokenTiersData memory mintTokenTiersData)
    {
        mintTokenTiersData = Storage.layout().mintTokenTiers;
    }

    /// @notice ensures a value is within the BASIS range
    /// @param value value to normalize
    /// @return normalizedValue value after normalization
    function _normalizeValue(
        uint256 value,
        uint32 basis
    ) internal pure returns (uint256 normalizedValue) {
        normalizedValue = value % basis;
    }

    /// @notice redeems an amount of $MINT tokens for ETH (native token) for an account
    /// @dev only one-sided ($MINT => ETH (native token)) supported
    /// @param account address of account
    /// @param amount amount of $MINT
    function _redeem(address account, uint256 amount) internal {
        Storage.Layout storage l = Storage.layout();

        if (l.redeemPaused) {
            revert RedeemPaused();
        }

        // burn amount of $MINT to be swapped
        IToken(l.mintToken).burn(account, amount);

        // calculate amount of ETH given for $MINT amount
        uint256 ethAmount = (amount * (BASIS - l.redemptionFeeBP)) /
            (BASIS * _ethToMintRatio(l));

        if (ethAmount > l.consolationFees) {
            revert InsufficientConsolationFees();
        }

        // decrease consolationFees
        l.consolationFees -= ethAmount;

        payable(account).sendValue(ethAmount);
    }

    /// @notice returns value of redeemPaused
    /// @return status boolean indicating whether redeeming is paused
    function _redeemPaused() internal view returns (bool status) {
        status = Storage.layout().redeemPaused;
    }

    /// @notice returns the current redemption fee in basis points
    /// @return feeBP redemptionFee in basis points
    function _redemptionFeeBP() internal view returns (uint32 feeBP) {
        feeBP = Storage.layout().redemptionFeeBP;
    }

    /// @notice requests random values from Chainlink VRF
    /// @param l the PerpetualMint storage layout
    /// @param collectionData the CollectionData struct for a given collection
    /// @param minter address calling this function
    /// @param collection address of collection to attempt mint for
    /// @param numWords amount of random values to request
    function _requestRandomWords(
        Storage.Layout storage l,
        CollectionData storage collectionData,
        address minter,
        address collection,
        uint32 numWords
    ) internal {
        VRFCoordinatorV2Interface vrfCoordinator = VRFCoordinatorV2Interface(
            VRF
        );

        (uint96 vrfSubscriptionBalance, , , ) = vrfCoordinator.getSubscription(
            l.vrfConfig.subscriptionId
        );

        if (vrfSubscriptionBalance < l.vrfSubscriptionBalanceThreshold) {
            revert VRFSubscriptionBalanceBelowThreshold();
        }

        uint256 requestId = vrfCoordinator.requestRandomWords(
            l.vrfConfig.keyHash,
            l.vrfConfig.subscriptionId,
            l.vrfConfig.minConfirmations,
            l.vrfConfig.callbackGasLimit,
            numWords
        );

        collectionData.pendingRequests.add(requestId);

        RequestData storage request = l.requests[requestId];

        request.collection = collection;
        request.minter = minter;
    }

    /// @notice requests random values from Supra VRF, Base-specific
    /// @param l the PerpetualMint storage layout
    /// @param collectionData the CollectionData struct for a given collection
    /// @param minter address calling this function
    /// @param collection address of collection to attempt mint for
    /// @param numWords amount of random values to request
    function _requestRandomWordsBase(
        Storage.Layout storage l,
        CollectionData storage collectionData,
        address minter,
        address collection,
        uint8 numWords
    ) internal {
        ISupraRouterContract supraRouter = ISupraRouterContract(VRF);

        uint256 requestId = supraRouter.generateRequest(
            "rawFulfillRandomWords(uint256,uint256[])",
            numWords,
            1, // number of confirmations
            _owner()
        );

        collectionData.pendingRequests.add(requestId);

        RequestData storage request = l.requests[requestId];

        request.collection = collection;
        request.minter = minter;
    }

    /// @notice resolves the outcomes of attempted mints for a given collection
    /// @param mintToken address of $MINT token
    /// @param collectionMintMultiplier mint multiplier of given collection
    /// @param collectionMintPrice mint price of given collection
    /// @param collectionRisk risk of given collection
    /// @param tiersData the TiersData struct for mint consolations
    /// @param minter address of minter
    /// @param collection address of collection for mint attempts
    /// @param randomWords array of random values relating to number of attempts
    /// @param ethToMintRatio ratio of ETH to $MINT
    function _resolveMints(
        address mintToken,
        uint256 collectionMintMultiplier,
        uint256 collectionMintPrice,
        uint32 collectionRisk,
        TiersData memory tiersData,
        address minter,
        address collection,
        uint256[] memory randomWords,
        uint256 ethToMintRatio
    ) internal {
        // ensure the number of random words is even
        // each valid mint attempt requires two random words
        if (randomWords.length % 2 != 0) {
            revert UnmatchedRandomWords();
        }

        uint256 totalMintAmount;
        uint256 totalReceiptAmount;

        for (uint256 i = 0; i < randomWords.length; i += 2) {
            // first random word is used to determine whether the mint attempt was successful
            uint256 firstNormalizedValue = _normalizeValue(
                randomWords[i],
                BASIS
            );

            // second random word is used to determine the consolation tier
            uint256 secondNormalizedValue = _normalizeValue(
                randomWords[i + 1],
                BASIS
            );

            // if the collection risk is less than the first normalized value, the mint attempt is unsuccessful
            // and the second normalized value is used to determine the consolation tier
            if (!(collectionRisk > firstNormalizedValue)) {
                uint256 tierMintAmount;
                uint256 cumulativeRisk;

                // iterate through tiers to find the tier that the random value falls into
                for (uint256 j = 0; j < tiersData.tierRisks.length; ++j) {
                    cumulativeRisk += tiersData.tierRisks[j];

                    // if the cumulative risk is greater than the second normalized value, the tier has been found
                    if (cumulativeRisk > secondNormalizedValue) {
                        tierMintAmount =
                            (tiersData.tierMultipliers[j] *
                                ethToMintRatio *
                                collectionMintPrice) /
                            BASIS;

                        break;
                    }
                }

                totalMintAmount += tierMintAmount;
            } else {
                // mint attempt is successful, so the total receipt amount is incremented
                ++totalReceiptAmount;
            }
        }

        // Mint the cumulative amounts at the end
        if (totalMintAmount > 0) {
            // Apply collection-specific multiplier
            totalMintAmount =
                (totalMintAmount * collectionMintMultiplier) /
                BASIS;

            IToken(mintToken).mint(minter, totalMintAmount);
        }

        if (totalReceiptAmount > 0) {
            _safeMint(
                minter,
                uint256(bytes32(abi.encode(collection))), // encode collection address as tokenId
                totalReceiptAmount,
                ""
            );
        }

        emit MintResult(
            minter,
            collection,
            randomWords.length / 2,
            totalMintAmount,
            totalReceiptAmount
        );
    }

    /// @notice resolves the outcomes of attempted mints for $MINT
    /// @param mintToken address of $MINT token
    /// @param mintForMintMultiplier minting for $MINT multiplier
    /// @param mintForMintPrice mint for $MINT mint price
    /// @param mintTokenTiersData the MintTokenTiersData struct for mint for $MINT consolations
    /// @param minter address of minter
    /// @param randomWords array of random values relating to number of attempts
    /// @param ethToMintRatio ratio of ETH to $MINT
    function _resolveMintsForMint(
        address mintToken,
        uint256 mintForMintMultiplier,
        uint256 mintForMintPrice,
        MintTokenTiersData memory mintTokenTiersData,
        address minter,
        uint256[] memory randomWords,
        uint256 ethToMintRatio
    ) internal {
        uint256 totalMintAmount;

        for (uint256 i = 0; i < randomWords.length; ++i) {
            // random word is used to determine the consolation tier
            uint256 normalizedValue = _normalizeValue(randomWords[i], BASIS);

            uint256 tierMintAmount;
            uint256 cumulativeRisk;

            // iterate through tiers to find the tier that the random value falls into
            for (uint256 j = 0; j < mintTokenTiersData.tierRisks.length; ++j) {
                cumulativeRisk += mintTokenTiersData.tierRisks[j];

                // if the cumulative risk is greater than the normalized value, the tier has been found
                if (cumulativeRisk > normalizedValue) {
                    tierMintAmount =
                        (mintTokenTiersData.tierMultipliers[j] *
                            ethToMintRatio *
                            mintForMintPrice) /
                        BASIS;

                    break;
                }
            }

            totalMintAmount += tierMintAmount;
        }

        // Mint the cumulative amounts at the end
        // Apply $MINT-specific multiplier
        totalMintAmount = (totalMintAmount * mintForMintMultiplier) / BASIS;

        IToken(mintToken).mint(minter, totalMintAmount);

        emit MintResult(
            minter,
            address(0),
            randomWords.length,
            totalMintAmount,
            0
        );
    }

    /// @notice sets the collection mint fee distribution ratio in basis points
    /// @param collection address of collection
    /// @param ratioBP collection mint fee distribution ratio in basis points
    function _setCollectionMintFeeDistributionRatioBP(
        address collection,
        uint32 ratioBP
    ) internal {
        _enforceBasis(ratioBP, BASIS);

        CollectionData storage collectionData = Storage.layout().collections[
            collection
        ];

        collectionData.mintFeeDistributionRatioBP = ratioBP;

        emit CollectionMintFeeRatioUpdated(collection, ratioBP);
    }

    /// @notice sets the mint multiplier for a given collection
    /// @param collection address of collection
    /// @param multiplier mint multiplier of the collection
    function _setCollectionMintMultiplier(
        address collection,
        uint256 multiplier
    ) internal {
        CollectionData storage collectionData = Storage.layout().collections[
            collection
        ];

        _enforceNoPendingMints(collectionData);

        collectionData.mintMultiplier = multiplier;

        emit CollectionMultiplierSet(collection, multiplier);
    }

    /// @notice set the mint price for a given collection
    /// @param collection address of collection
    /// @param price mint price of the collection
    function _setCollectionMintPrice(
        address collection,
        uint256 price
    ) internal {
        Storage.layout().collections[collection].mintPrice = price;

        emit MintPriceSet(collection, price);
    }

    /// @notice sets the risk for a given collection
    /// @param collection address of collection
    /// @param risk risk of the collection
    function _setCollectionRisk(address collection, uint32 risk) internal {
        CollectionData storage collectionData = Storage.layout().collections[
            collection
        ];

        _enforceBasis(risk, BASIS);

        _enforceNoPendingMints(collectionData);

        collectionData.risk = risk;

        emit CollectionRiskSet(collection, risk);
    }

    /// @notice sets the mint for collection consolation fee in basis points
    /// @param collectionConsolationFeeBP mint for collection consolation fee in basis points
    function _setCollectionConsolationFeeBP(
        uint32 collectionConsolationFeeBP
    ) internal {
        _enforceBasis(collectionConsolationFeeBP, BASIS);

        Storage
            .layout()
            .collectionConsolationFeeBP = collectionConsolationFeeBP;

        emit CollectionConsolationFeeSet(collectionConsolationFeeBP);
    }

    /// @notice sets the ratio of ETH (native token) to $MINT for mint attempts using $MINT as payment
    /// @param ratio new ratio of ETH to $MINT
    function _setEthToMintRatio(uint256 ratio) internal {
        Storage.layout().ethToMintRatio = ratio;

        emit EthToMintRatioSet(ratio);
    }

    /// @notice sets the mint fee in basis points
    /// @param mintFeeBP mint fee in basis points
    function _setMintFeeBP(uint32 mintFeeBP) internal {
        _enforceBasis(mintFeeBP, BASIS);

        Storage.layout().mintFeeBP = mintFeeBP;

        emit MintFeeSet(mintFeeBP);
    }

    /// @notice sets the address of the mint consolation token
    /// @param mintToken address of the mint consolation token
    function _setMintToken(address mintToken) internal {
        Storage.layout().mintToken = mintToken;

        emit MintTokenSet(mintToken);
    }

    /// @notice sets the mint for $MINT consolation fee in basis points
    /// @param mintTokenConsolationFeeBP mint for $MINT consolation fee in basis points
    function _setMintTokenConsolationFeeBP(
        uint32 mintTokenConsolationFeeBP
    ) internal {
        _enforceBasis(mintTokenConsolationFeeBP, BASIS);

        Storage.layout().mintTokenConsolationFeeBP = mintTokenConsolationFeeBP;

        emit MintTokenConsolationFeeSet(mintTokenConsolationFeeBP);
    }

    /// @notice sets the mint for $MINT tiers data
    /// @param mintTokenTiersData MintTokenTiersData struct holding all related data to mint for $MINT consolations
    function _setMintTokenTiers(
        MintTokenTiersData calldata mintTokenTiersData
    ) internal {
        Storage.layout().mintTokenTiers = mintTokenTiersData;

        emit MintTokenTiersSet(mintTokenTiersData);
    }

    /// @notice sets the status of the redeemPaused state
    /// @param status boolean indicating whether redeeming is paused
    function _setRedeemPaused(bool status) internal {
        Storage.layout().redeemPaused = status;

        emit RedeemPausedSet(status);
    }

    /// @notice sets the redemption fee in basis points
    /// @param redemptionFeeBP redemption fee in basis points
    function _setRedemptionFeeBP(uint32 redemptionFeeBP) internal {
        _enforceBasis(redemptionFeeBP, BASIS);

        Storage.layout().redemptionFeeBP = redemptionFeeBP;

        emit RedemptionFeeSet(redemptionFeeBP);
    }

    /// @notice sets the mint for collection $MINT consolation tiers data
    /// @param tiersData TiersData struct holding all related data to mint for collection $MINT consolations
    function _setTiers(TiersData calldata tiersData) internal {
        Storage.layout().tiers = tiersData;

        emit TiersSet(tiersData);
    }

    /// @notice sets the Chainlink VRF config
    /// @param config VRFConfig struct holding all related data to ChainlinkVRF
    function _setVRFConfig(VRFConfig calldata config) internal {
        Storage.layout().vrfConfig = config;

        emit VRFConfigSet(config);
    }

    /// @notice sets the Chainlink VRF subscription LINK balance threshold
    /// @param vrfSubscriptionBalanceThreshold VRF subscription balance threshold
    function _setVRFSubscriptionBalanceThreshold(
        uint96 vrfSubscriptionBalanceThreshold
    ) internal {
        Storage
            .layout()
            .vrfSubscriptionBalanceThreshold = vrfSubscriptionBalanceThreshold;

        emit VRFSubscriptionBalanceThresholdSet(
            vrfSubscriptionBalanceThreshold
        );
    }

    /// @notice Returns the current tier risks and multipliers for minting for collection $MINT consolations
    function _tiers() internal view returns (TiersData memory tiersData) {
        tiersData = Storage.layout().tiers;
    }

    /// @notice Returns the current Chainlink VRF config
    /// @return config VRFConfig struct
    function _vrfConfig() internal view returns (VRFConfig memory config) {
        config = Storage.layout().vrfConfig;
    }

    /// @notice Returns the current Chainlink VRF subscription LINK balance threshold
    /// @return vrfSubscriptionBalanceThreshold VRF subscription balance threshold
    function _vrfSubscriptionBalanceThreshold()
        internal
        view
        returns (uint96 vrfSubscriptionBalanceThreshold)
    {
        vrfSubscriptionBalanceThreshold = Storage
            .layout()
            .vrfSubscriptionBalanceThreshold;
    }
}

