// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import "./MultiToken.sol";

import "./MerkleProof.sol";

import "./PWNSignatureChecker.sol";
import "./PWNSimpleLoanOffer.sol";
import "./PWNLOANTerms.sol";
import "./PWNErrors.sol";


/**
 * @title PWN Simple Loan List Offer
 * @notice Loan terms factory contract creating a simple loan terms from a list offer.
 * @dev This offer can be used as a collection offer or define a list of acceptable ids from a collection.
 */
contract PWNSimpleLoanListOffer is PWNSimpleLoanOffer {

    string internal constant VERSION = "1.1";

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * @dev EIP-712 simple offer struct type hash.
     */
    bytes32 constant internal OFFER_TYPEHASH = keccak256(
        "Offer(uint8 collateralCategory,address collateralAddress,bytes32 collateralIdsWhitelistMerkleRoot,uint256 collateralAmount,address loanAssetAddress,uint256 loanAmount,uint256 loanYield,uint32 duration,uint40 expiration,address borrower,address lender,bool isPersistent,uint256 nonce)"
    );

    bytes32 immutable internal DOMAIN_SEPARATOR;

    /**
     * @notice Construct defining a list offer.
     * @param collateralCategory Category of an asset used as a collateral (0 == ERC20, 1 == ERC721, 2 == ERC1155).
     * @param collateralAddress Address of an asset used as a collateral.
     * @param collateralIdsWhitelistMerkleRoot Merkle tree root of a set of whitelisted collateral ids.
     * @param collateralAmount Amount of tokens used as a collateral, in case of ERC721 should be 0.
     * @param loanAssetAddress Address of an asset which is lender to a borrower.
     * @param loanAmount Amount of tokens which is offered as a loan to a borrower.
     * @param loanYield Amount of tokens which acts as a lenders loan interest. Borrower has to pay back a borrowed amount + yield.
     * @param duration Loan duration in seconds.
     * @param expiration Offer expiration timestamp in seconds.
     * @param borrower Address of a borrower. Only this address can accept an offer. If the address is zero address, anybody with a collateral can accept the offer.
     * @param lender Address of a lender. This address has to sign an offer to be valid.
     * @param isPersistent If true, offer will not be revoked on acceptance. Persistent offer can be revoked manually.
     * @param nonce Additional value to enable identical offers in time. Without it, it would be impossible to make again offer, which was once revoked.
     *              Can be used to create a group of offers, where accepting one offer will make other offers in the group revoked.
     */
    struct Offer {
        MultiToken.Category collateralCategory;
        address collateralAddress;
        bytes32 collateralIdsWhitelistMerkleRoot;
        uint256 collateralAmount;
        address loanAssetAddress;
        uint256 loanAmount;
        uint256 loanYield;
        uint32 duration;
        uint40 expiration;
        address borrower;
        address lender;
        bool isPersistent;
        uint256 nonce;
    }

    /**
     * Construct defining an Offer concrete values
     * @param collateralId Selected collateral id to be used as a collateral.
     * @param merkleInclusionProof Proof of inclusion, that selected collateral id is whitelisted.
     *                             This proof should create same hash as the merkle tree root given in an Offer.
     *                             Can be empty for collection offers.
     */
    struct OfferValues {
        uint256 collateralId;
        bytes32[] merkleInclusionProof;
    }


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address hub, address _revokedOfferNonce) PWNSimpleLoanOffer(hub, _revokedOfferNonce) {
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("PWNSimpleLoanListOffer"),
            keccak256("1"),
            block.chainid,
            address(this)
        ));
    }


    /*----------------------------------------------------------*|
    |*  # OFFER MANAGEMENT                                      *|
    |*----------------------------------------------------------*/

    /**
     * @notice Make an on-chain offer.
     * @dev Function will mark an offer hash as proposed. Offer will become acceptable by a borrower without an offer signature.
     * @param offer Offer struct containing all needed offer data.
     */
    function makeOffer(Offer calldata offer) external {
        _makeOffer(getOfferHash(offer), offer.lender);
    }


    /*----------------------------------------------------------*|
    |*  # IPWNSimpleLoanFactory                                 *|
    |*----------------------------------------------------------*/

    /**
     * @notice See { IPWNSimpleLoanFactory.sol }.
     */
    function createLOANTerms(
        address caller,
        bytes calldata factoryData,
        bytes calldata signature
    ) external override onlyActiveLoan returns (PWNLOANTerms.Simple memory loanTerms, bytes32 offerHash) {

        (Offer memory offer, OfferValues memory offerValues) = abi.decode(factoryData, (Offer, OfferValues));
        offerHash = getOfferHash(offer);

        address lender = offer.lender;
        address borrower = caller;

        // Check that offer has been made via on-chain tx, EIP-1271 or signed off-chain
        if (offersMade[offerHash] == false)
            if (PWNSignatureChecker.isValidSignatureNow(lender, offerHash, signature) == false)
                revert InvalidSignature();

        // Check valid offer
        if (offer.expiration != 0 && block.timestamp >= offer.expiration)
            revert OfferExpired();

        if (revokedOfferNonce.isNonceRevoked(lender, offer.nonce) == true)
            revert NonceAlreadyRevoked();

        if (offer.borrower != address(0))
            if (borrower != offer.borrower)
                revert CallerIsNotStatedBorrower(offer.borrower);

        if (offer.duration < MIN_LOAN_DURATION)
            revert InvalidDuration();

        // Collateral id list
        if (offer.collateralIdsWhitelistMerkleRoot != bytes32(0)) {
            // Verify whitelisted collateral id
            bool isVerifiedId = MerkleProof.verify(
                offerValues.merkleInclusionProof,
                offer.collateralIdsWhitelistMerkleRoot,
                keccak256(abi.encodePacked(offerValues.collateralId))
            );
            if (isVerifiedId == false)
                revert CollateralIdIsNotWhitelisted();
        } // else: Any collateral id - collection offer

        // Prepare collateral and loan asset
        MultiToken.Asset memory collateral = MultiToken.Asset({
            category: offer.collateralCategory,
            assetAddress: offer.collateralAddress,
            id: offerValues.collateralId,
            amount: offer.collateralAmount
        });
        MultiToken.Asset memory loanAsset = MultiToken.Asset({
            category: MultiToken.Category.ERC20,
            assetAddress: offer.loanAssetAddress,
            id: 0,
            amount: offer.loanAmount
        });

        // Create loan object
        loanTerms = PWNLOANTerms.Simple({
            lender: lender,
            borrower: borrower,
            expiration: uint40(block.timestamp) + offer.duration,
            collateral: collateral,
            asset: loanAsset,
            loanRepayAmount: offer.loanAmount + offer.loanYield
        });

        // Revoke offer if not persistent
        if (!offer.isPersistent)
            revokedOfferNonce.revokeNonce(lender, offer.nonce);
    }


    /*----------------------------------------------------------*|
    |*  # GET OFFER HASH                                        *|
    |*----------------------------------------------------------*/

    /**
     * @notice Get an offer hash according to EIP-712
     * @param offer Offer struct to be hashed.
     * @return Offer struct hash.
     */
    function getOfferHash(Offer memory offer) public view returns (bytes32) {
        return keccak256(abi.encodePacked(
            hex"1901",
            DOMAIN_SEPARATOR,
            keccak256(abi.encodePacked(
                OFFER_TYPEHASH,
                abi.encode(offer)
            ))
        ));
    }


    /*----------------------------------------------------------*|
    |*  # LOAN TERMS FACTORY DATA ENCODING                      *|
    |*----------------------------------------------------------*/

    /**
     * @notice Return encoded input data for this loan terms factory.
     * @param offer Simple loan list offer struct to encode.
     * @param offerValues Simple loan list offer concrete values from borrower.
     * @return Encoded loan terms factory data that can be used as an input of `createLOANTerms` function with this factory.
     */
    function encodeLoanTermsFactoryData(Offer memory offer, OfferValues memory offerValues) external pure returns (bytes memory) {
        return abi.encode(offer, offerValues);
    }

}

