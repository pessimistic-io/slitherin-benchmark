// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { PaymentType } from "./LibStorage.sol";

interface IBattleflyGame {
    function createCredit(
        uint256 creditType,
        uint256 amount,
        PaymentType paymentType,
        uint256[] memory treasureIds,
        uint256[] memory treasureAmounts
    ) external;

    function upgradeInventorySlot(
        uint256 battleflyId,
        uint256 amount,
        PaymentType paymentType,
        uint256[] memory treasureIds,
        uint256[] memory treasureAmounts
    ) external;

    function isCreditType(uint256 creditTypeId) external view returns (bool);

    function getGFlyPerCredit() external view returns (uint256);

    function getTreasuresPerCredit() external view returns (uint256);

    function getGFlyReceiver() external view returns (address);

    function getTreasureReceiver() external view returns (address);

    function gFlyAddress() external view returns (address);

    function treasuresAddress() external view returns (address);

    function stakeSoulbound(address owner, uint256 tokenId) external;

    function bulkStakeBattlefly(uint256[] memory tokenIds) external;

    function bulkUnstakeBattlefly(
        uint256[] memory tokenIds,
        uint256[] memory battleflyStages,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function stakingBattlefliesOfOwner(address owner) external view returns (uint256[] memory);

    function balanceOf(address owner) external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function rollOverProcessingEpoch() external;

    function depositMagicRNGEmissions(uint256 depositAmountInWei, uint256 gameAmountInWei) external;

    function claimEmissions(uint256 index, uint256 epoch, bytes calldata data, bytes32[] calldata merkleProof) external;

    function setMerkleRoot(bytes32 root) external;

    function getClaimableMagicRNGEmissionsFor(address account, bytes calldata data) external view returns (uint256);

    function getClaimedMagicRNGEmissionsFor(address account) external view returns (uint256);

    function getMerkleRoot() external view returns (bytes32);

    function getEmissionsEpoch() external view returns (uint256);

    function getProcessingEpoch() external view returns (uint256);

    function pay(
        uint256 currency,
        uint256 productType,
        uint256 pricePerProductTypeInMagic,
        uint256 productTypeAmount
    ) external;

    function getPaymentReceiver() external view returns (address);

    function getUSDC() external view returns (address);

    function getUSDCOriginal() external view returns (address);

    function getAmountOfCurrencyForXMagic(uint256 currency, uint256 magicAmount) external view returns (uint256);

    function transferMagicToGameContract() external;

    function getMagicReserve() external view returns (uint256);

    function getEthReserve() external view returns (uint256);

    function getUsdcReserve() external view returns (uint256);

    function getUsdcOriginalReserve() external view returns (uint256);

    function getWETH() external view returns (address);

    function getUSDCDataFeedAddress() external view returns (address);

    function getEthDataFeedAddress() external view returns (address);

    function getMagicDataFeedAddress() external view returns (address);

    function getSushiswapRouter() external view returns (address);

    function getUniswapV3Router() external view returns (address);

    function getUniswapV3Quoter() external view returns (address);

    function getUsdcToUsdcOriginalPoolFee() external view returns (uint24);
}

