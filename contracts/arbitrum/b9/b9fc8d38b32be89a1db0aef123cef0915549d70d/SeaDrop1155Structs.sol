// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @notice A struct defining public drop data.
 *         Designed to fit efficiently in one storage slot.
 * 
 * @param startTime                The start time, ensure this is not zero.
 * @param endTIme                  The end time, ensure this is not zero.
 * @param maxTotalMintableByWallet Maximum total number of mints a user is
 *                                 allowed. (The limit for this field is
 *                                 2^16 - 1)
 */
struct PublicDrop {
    uint256 startTime; // 128/256 bits
    uint256 endTime; // 176/256 bits
    uint256 maxTotalMintableByWallet; // 224/256 bits
    uint256 maxTokenSupplyForStage;
    uint8 startMode;
}


/**
 * @notice A struct defining private drop data.
 *         Designed to fit efficiently in one storage slot.
 * 
 * @param maxTotalMintableByWallet Maximum total number of mints a user is
 *                                 allowed.
 * @param startTime                The start time, ensure this is not zero.
 * @param endTime                  The end time, ensure this is not zero.
 * @param maxTokenSupplyForStage   The limit of token supply this stage can
 *                                 mint within.
 */
struct PrivateDrop {
    uint256 startTime;
    uint256 endTime;
    uint256 maxTotalMintableByWallet;
    uint256 maxTokenSupplyForStage;
    uint8 startMode;
}

/**
 * @notice A struct defining white list data.
 *         Designed to fit efficiently in one storage slot.
 * 
 * @param maxTotalMintableByWallet Maximum total number of mints a user is
 *                                 allowed.
 * @param startTime                The start time, ensure this is not zero.
 * @param endTime                  The end time, ensure this is not zero.
 * @param maxTokenSupplyForStage   The limit of token supply this stage can
 *                                 mint within.
 */
struct WhiteList {
    uint256 startTime;
    uint256 endTime;
    uint256 maxTotalMintableByWallet;
    uint256 maxTokenSupplyForStage;
    uint8 startMode;
}

/**
* @notice A struct to configure multiple contract options at a time.
*/
struct MultiConfigure {
    uint256 maxSupply;
    address seaDropImpl;
    PublicDrop publicDrop;
    PrivateDrop privateDrop;
    WhiteList whiteList;
    address creatorPayoutAddress;
    address signer;
}

/** 
 * @notice A struct defining mint stats.
 */
struct MintStats {
    uint256 maxSupply;
    uint256 totalMinted;
}

struct AirDropParam {
    address nftRecipient;
    uint256 tokenId;
    uint256 quantity;
}


