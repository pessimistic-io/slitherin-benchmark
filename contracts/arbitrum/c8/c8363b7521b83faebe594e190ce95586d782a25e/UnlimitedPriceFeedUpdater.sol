// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./EIP712Upgradeable.sol";
import "./SignatureCheckerUpgradeable.sol";
import "./IController.sol";
import "./IUpdatable.sol";

/**
 * @notice Struct to store the price feed data.
 * @custom:member createdOn The timestamp when the price data was stored.
 * @custom:member validTo The timestamp until which the price data is valid.
 * @custom:member price The price.
 */
struct PriceData {
    uint32 createdOn;
    uint32 validTo;
    int192 price;
}

/**
 * @title Unlimited Price Feed
 * @notice Unlimited Price Feed is a price feed that can be updated by anyone.
 * To update the price feed, the caller must provide a UpdateData struct that contains
 * a valid signature from the registered signer. Price Updates contained must by valid and more recent than
 * the last update. The price feed will only accept updates that are within the validTo period.
 * The price may only deviate at a set percentage from the chainlink price feed.
 */
abstract contract UnlimitedPriceFeedUpdater is EIP712Upgradeable, IUpdatable {
    /* ========== CONSTANTS ========== */

    uint256 private constant SIGNATURE_END = 65;
    uint256 private constant WORD_LENGTH = 32;
    uint256 private constant SIGNER_END = SIGNATURE_END + WORD_LENGTH;
    uint256 private constant DATA_LENGTH = SIGNER_END + WORD_LENGTH * 3;

    /* ========== STATE VARIABLES ========== */

    /// @notice Controller contract.
    IController public immutable controller;
    /// @notice Recent price data. It gets updated with each valid update request.
    PriceData public priceData;

    /**
     * @notice Constructs the UnlimitedPriceFeedUpdater contract.
     * @param controller_ The address of the controller contract.
     */
    constructor(IController controller_) {
        controller = controller_;
    }

    /**
     * @notice Initializes the underlying EIP712 contract
     * @param name_ the user readable name of the signing domain, i.e. the name of the DApp or the protocol.
     */
    function __UnlimitedPriceFeedUpdater_init(string memory name_) internal onlyInitializing {
        __EIP712_init(name_, "1");
    }

    /**
     * @notice Returns last price
     * @return the price from the last round
     */
    function _price() internal view verifyPriceValidity returns (int256) {
        return priceData.price;
    }

    /**
     * @notice Update price with signed data.
     * @param updateData_ Data bytes consisting of signature, signer and price data in respected order.
     */
    function update(bytes calldata updateData_) external {
        require(updateData_.length == DATA_LENGTH, "UnlimitedPriceFeedUpdater::update: Bad data length");

        PriceData memory newPriceData = abi.decode(updateData_[SIGNER_END:], (PriceData));

        // Verify new price data is more recent than the current price data
        // Return if the new price data is not more recent
        if (newPriceData.createdOn <= priceData.createdOn) {
            return;
        }

        // verify signer access controlls
        address signer = abi.decode(updateData_[SIGNATURE_END:SIGNER_END], (address));

        // throw if the signer is not allowed to update the price
        _verifySigner(signer);

        // verify signature
        bytes calldata signature = updateData_[:SIGNATURE_END];
        require(
            SignatureCheckerUpgradeable.isValidSignatureNow(signer, _hashPriceDataUpdate(newPriceData), signature),
            "UnlimitedPriceFeedUpdater::update: Bad signature"
        );

        // verify validity of data
        _verifyValidTo(newPriceData.validTo);

        _verifyNewPrice(newPriceData.price);

        priceData = newPriceData;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _hashPriceDataUpdate(PriceData memory priceData_) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(address(this), priceData_)));
    }

    function _verifyNewPrice(int256 newPrice) internal view virtual;

    /* ========== RESTRICTION FUNCTIONS ========== */

    function _verifyValidTo(uint256 validTo_) private view {
        require(validTo_ >= block.timestamp, "UnlimitedPriceFeedUpdater::_verifyValidTo: Price is not valid");
    }

    function _verifySigner(address signer_) private view {
        require(controller.isSigner(signer_), "UnlimitedPriceFeedUpdater::_verifySigner: Bad signer");
    }

    /* ========== MODIFIERS ========== */

    modifier verifyPriceValidity() {
        _verifyValidTo(priceData.validTo);
        _;
    }
}

