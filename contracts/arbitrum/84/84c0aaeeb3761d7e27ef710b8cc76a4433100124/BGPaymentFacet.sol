// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Storage imports
import { WithModifiers } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

// Library imports
import { LibPaymentUtils } from "./LibPaymentUtils.sol";

// Contract imports
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

contract BGPaymentFacet is WithModifiers, ReentrancyGuard {
    event PaymentMade(
        address account,
        uint256 currency,
        uint256 productType,
        uint256 pricePerProductTypeInMagic,
        uint256 productTypeAmount
    );

    event USDCPaymentMade(
        address account,
        uint256 currency,
        uint256 productType,
        uint256 pricePerProductTypeInUSDC,
        uint256 productTypeAmount
    );

    event MagicTransferredToGameContract(
        address account,
        uint256 magicAmount,
        uint256 treasuryEthAmount,
        uint256 treasuryMagicAmount,
        uint256 treasuryUsdcAmount,
        uint256 treasuryUsdcOriginalAmount,
        uint256 treasuryArbAmount
    );

    // Currencies: 0 = ETH, 1 = Magic, 2 = USDCe, 3 = USDC Original (Circle), 4 = ARB
    function pay(
        uint256 currency,
        uint256 productType,
        uint256 pricePerProductTypeInMagic,
        uint256 productTypeAmount
    ) external payable notPaused nonReentrant {
        LibPaymentUtils.pay(currency, productType, pricePerProductTypeInMagic, productTypeAmount, msg.value);
    }

    // Currencies: 0 = ETH, 1 = Magic, 2 = USDCe, 3 = USDC Original (Circle), 4 = ARB
    function payUSDC(
        uint256 currency,
        uint256 productType,
        uint256 pricePerProductTypeInUSDC,
        uint256 productTypeAmount
    ) external payable notPaused nonReentrant {
        LibPaymentUtils.payUSDC(currency, productType, pricePerProductTypeInUSDC, productTypeAmount, msg.value);
    }

    function getPaymentReceiver() external view returns (address) {
        return LibPaymentUtils.getPaymentReceiver();
    }

    function getUSDC() external view returns (address) {
        return LibPaymentUtils.getUSDC();
    }

    function getArb() external view returns (address) {
        return LibPaymentUtils.getArb();
    }

    function getUSDCOriginal() external view returns (address) {
        return LibPaymentUtils.getUSDCOriginal();
    }

    function getAmountOfCurrencyForXMagic(uint256 currency, uint256 magicAmount) external view returns (uint256) {
        return LibPaymentUtils.getAmountOfCurrencyForXMagic(currency, magicAmount);
    }

    function getAmountOfCurrencyForXUSDC(uint256 currency, uint256 usdcAmount) external view returns (uint256) {
        return LibPaymentUtils.getAmountOfCurrencyForXUSDC(currency, usdcAmount);
    }

    function transferMagicToGameContract() external notPaused onlyGameV2 {
        LibPaymentUtils.transferMagicToGameContract();
    }

    function getMagicReserve() external view returns (uint256) {
        return LibPaymentUtils.getMagicReserve();
    }

    function getEthReserve() external view returns (uint256) {
        return LibPaymentUtils.getEthReserve();
    }

    function getUsdcReserve() external view returns (uint256) {
        return LibPaymentUtils.getUsdcReserve();
    }

    function getUsdcOriginalReserve() external view returns (uint256) {
        return LibPaymentUtils.getUsdcOriginalReserve();
    }

    function getArbReserve() external view returns (uint256) {
        return LibPaymentUtils.getArbReserve();
    }

    function getWETH() external view returns (address) {
        return LibPaymentUtils.getWETH();
    }

    function getUSDCDataFeedAddress() external view returns (address) {
        return LibPaymentUtils.getUSDCDataFeedAddress();
    }

    function getEthDataFeedAddress() external view returns (address) {
        return LibPaymentUtils.getEthDataFeedAddress();
    }

    function getMagicDataFeedAddress() external view returns (address) {
        return LibPaymentUtils.getMagicDataFeedAddress();
    }

    function getArbDataFeedAddress() external view returns (address) {
        return LibPaymentUtils.getArbDataFeedAddress();
    }

    function getSushiswapRouter() external view returns (address) {
        return LibPaymentUtils.getSushiswapRouter();
    }

    function getUniswapV3Router() external view returns (address) {
        return LibPaymentUtils.getUniswapV3Router();
    }

    function getUniswapV3Quoter() external view returns (address) {
        return LibPaymentUtils.getUniswapV3Quoter();
    }

    function getUsdcToUsdcOriginalPoolFee() external view returns (uint24) {
        return LibPaymentUtils.getUsdcToUsdcOriginalPoolFee();
    }

    function getSequencerUptimeFeedAddress() external view returns (address) {
        return LibPaymentUtils.getSequencerUptimeFeedAddress();
    }

    function getSequencerGracePeriod() external view returns (uint256) {
        return LibPaymentUtils.getSequencerGracePeriod();
    }
}

