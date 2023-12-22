// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./IController.sol";
import "./ITradePair.sol";
import "./IUserManager.sol";

// =============================================================
//                           STRUCTS
// =============================================================

/**
 * @notice Parameters for opening a position
 * @custom:member tradePair The trade pair to open the position on
 * @custom:member margin The amount of margin to use for the position
 * @custom:member leverage The leverage to open the position with
 * @custom:member isShort Whether the position is a short position
 * @custom:member referrer The address of the referrer or zero
 * @custom:member whitelabelAddress The address of the whitelabel or zero
 */
struct OpenPositionParams {
    address tradePair;
    uint256 margin;
    uint256 leverage;
    bool isShort;
    address referrer;
    address whitelabelAddress;
}

/**
 * @notice Parameters for closing a position
 * @custom:member tradePair The trade pair to close the position on
 * @custom:member positionId The id of the position to close
 */
struct ClosePositionParams {
    address tradePair;
    uint256 positionId;
}

/**
 * @notice Parameters for partially closing a position
 * @custom:member tradePair The trade pair to add margin to
 * @custom:member positionId The id of the position to add margin to
 * @custom:member proportion the proportion of the position to close
 * @custom:member leaveLeverageFactor the leaveLeverage / takeProfit factor
 */
struct PartiallyClosePositionParams {
    address tradePair;
    uint256 positionId;
    uint256 proportion;
}

/**
 * @notice Parameters for removing margin from a position
 * @custom:member tradePair The trade pair to add margin to
 * @custom:member positionId The id of the position to add margin to
 * @custom:member removedMargin The amount of margin to remove
 */
struct RemoveMarginFromPositionParams {
    address tradePair;
    uint256 positionId;
    uint256 removedMargin;
}

/**
 * @notice Parameters for adding margin to a position
 * @custom:member tradePair The trade pair to add margin to the position on
 * @custom:member positionId The id of the position to add margin to
 * @custom:member addedMargin The amount of margin to add
 */
struct AddMarginToPositionParams {
    address tradePair;
    uint256 positionId;
    uint256 addedMargin;
}

/**
 * @notice Parameters for extending a position
 * @custom:member tradePair The trade pair to add margin to the position on
 * @custom:member positionId The id of the position to add margin to
 * @custom:member addedMargin The amount of margin to add
 * @custom:member addedLeverage The leverage used on the addedMargin
 */
struct ExtendPositionParams {
    address tradePair;
    uint256 positionId;
    uint256 addedMargin;
    uint256 addedLeverage;
}

/**
 * @notice Parameters for extending a position to a target leverage
 * @custom:member tradePair The trade pair to add margin to the position on
 * @custom:member positionId The id of the position to add margin to
 * @custom:member targetLeverage the target leverage to close to
 */
struct ExtendPositionToLeverageParams {
    address tradePair;
    uint256 positionId;
    uint256 targetLeverage;
}

/**
 * @notice Constraints to constraint the opening, alteration or closing of a position
 * @custom:member deadline The deadline for the transaction
 * @custom:member minPrice a minimum price for the transaction
 * @custom:member maxPrice a maximum price for the transaction
 */
struct Constraints {
    uint256 deadline;
    int256 minPrice;
    int256 maxPrice;
}

/**
 * @notice Parameters for opening a position
 * @custom:member params The parameters for opening a position
 * @custom:member constraints The constraints for opening a position
 * @custom:member salt Salt to ensure uniqueness of signed message
 */
struct OpenPositionOrder {
    OpenPositionParams params;
    Constraints constraints;
    uint256 salt;
}

/**
 * @notice Parameters for closing a position
 * @custom:member params The parameters for closing a position
 * @custom:member constraints The constraints for closing a position
 * @custom:member signatureHash The signatureHash of the open position order, when this is an automated order
 * @custom:member salt Salt to ensure uniqueness of signed message
 */
struct ClosePositionOrder {
    ClosePositionParams params;
    Constraints constraints;
    bytes32 signatureHash;
    uint256 salt;
}

/**
 * @notice Parameters for partially closing a position
 * @custom:member params The parameters for partially closing a position
 * @custom:member constraints The constraints for partially closing a position
 * @custom:member signatureHash The signatureHash of the open position order, when this is an automated order
 * @custom:member salt Salt to ensure uniqueness of signed message
 */
struct PartiallyClosePositionOrder {
    PartiallyClosePositionParams params;
    Constraints constraints;
    bytes32 signatureHash;
    uint256 salt;
}

/**
 * @notice Parameters for extending a position
 * @custom:member params The parameters for extending a position
 * @custom:member constraints The constraints for extending a position
 * @custom:member signatureHash The signatureHash of the open position order, when this is an automated order
 * @custom:member salt Salt to ensure uniqueness of signed message
 */
struct ExtendPositionOrder {
    ExtendPositionParams params;
    Constraints constraints;
    bytes32 signatureHash;
    uint256 salt;
}

/**
 * @notice Parameters for extending a position to leverage
 * @custom:member params The parameters for extending a position to leverage
 * @custom:member constraints The constraints for extending a position to leverage
 * @custom:member signatureHash The signatureHash of the open position order, when this is an automated order
 * @custom:member salt Salt to ensure uniqueness of signed message
 */
struct ExtendPositionToLeverageOrder {
    ExtendPositionToLeverageParams params;
    Constraints constraints;
    bytes32 signatureHash;
    uint256 salt;
}

/**
 * @notice Parameters foradding margin to a position
 * @custom:member params The parameters foradding margin to a position
 * @custom:member constraints The constraints foradding margin to a position
 * @custom:member signatureHash The signatureHash of the open position order, when this is an automated order
 * @custom:member salt Salt to ensure uniqueness of signed message
 */
struct AddMarginToPositionOrder {
    AddMarginToPositionParams params;
    Constraints constraints;
    bytes32 signatureHash;
    uint256 salt;
}

/**
 * @notice Parameters for removing margin from a position
 * @custom:member params The parameters for removing margin from a position
 * @custom:member constraints The constraints for removing margin from a position
 * @custom:member signatureHash The signatureHash of the open position order, when this is an automated order
 * @custom:member salt Salt to ensure uniqueness of signed message
 */
struct RemoveMarginFromPositionOrder {
    RemoveMarginFromPositionParams params;
    Constraints constraints;
    bytes32 signatureHash;
    uint256 salt;
}

/**
 * @notice UpdateData for updatable contracts like the UnlimitedPriceFeed
 * @custom:member updatableContract The address of the updatable contract
 * @custom:member data The data to update the contract with
 */
struct UpdateData {
    address updatableContract;
    bytes data;
}

/**
 * @notice Struct to store tradePair and positionId together.
 * @custom:member tradePair the address of the tradePair
 * @custom:member positionId the positionId of the position
 */
struct TradeId {
    address tradePair;
    uint96 positionId;
}

interface ITradeManager {
    /* ========== EVENTS ========== */

    event PositionOpened(address indexed tradePair, uint256 indexed id);

    event PositionClosed(address indexed tradePair, uint256 indexed id);

    event PositionPartiallyClosed(address indexed tradePair, uint256 indexed id, uint256 proportion);

    event PositionLiquidated(address indexed tradePair, uint256 indexed id);

    event PositionExtended(address indexed tradePair, uint256 indexed id, uint256 addedMargin, uint256 addedLeverage);

    event PositionExtendedToLeverage(address indexed tradePair, uint256 indexed id, uint256 targetLeverage);

    event MarginAddedToPosition(address indexed tradePair, uint256 indexed id, uint256 addedMargin);

    event MarginRemovedFromPosition(address indexed tradePair, uint256 indexed id, uint256 removedMargin);

    /* ========== CORE FUNCTIONS - LIQUIDATIONS ========== */

    function liquidatePosition(address tradePair, uint256 positionId, UpdateData[] calldata updateData) external;

    function batchLiquidatePositions(
        address[] calldata tradePairs,
        uint256[][] calldata positionIds,
        bool allowRevert,
        UpdateData[] calldata updateData
    ) external returns (bool[][] memory didLiquidate);

    /* =========== VIEW FUNCTIONS ========== */

    function detailsOfPosition(address tradePair, uint256 positionId) external view returns (PositionDetails memory);

    function positionIsLiquidatable(address tradePair, uint256 positionId) external view returns (bool);

    function canLiquidatePositions(address[] calldata tradePairs, uint256[][] calldata positionIds)
        external
        view
        returns (bool[][] memory canLiquidate);

    function canLiquidatePositionsAtPrices(
        address[] calldata tradePairs_,
        uint256[][] calldata positionIds_,
        int256[] calldata prices_
    ) external view returns (bool[][] memory canLiquidate);

    function getCurrentFundingFeeRates(address tradePair) external view returns (int256, int256);

    function totalVolumeLimitOfTradePair(address tradePair_) external view returns (uint256);
}

