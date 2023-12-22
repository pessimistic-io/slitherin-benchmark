// SPDX-License-Identifier: MIT

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//      \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//       \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//        \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//         \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|
//

pragma solidity 0.8.19;
import "./USDEngineAbstract.sol";

/*
 * Title: USDEngine
 * Author: Torque Inc.
 * Collateral: Exogenous
 * Minting: Algorithmic
 * Stability: USD Peg
 * Collateral: Crypto
 *
 * This contract is the core of USD.money. It handles the USD 'mint
 * and redeem' logic and is based on the MakerDAO DSS system.
 */
contract USDEngine is USDEngineAbstract {
    ///////////////////
    // Functions
    ///////////////////

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        uint256[] memory liquidationThresholds,
        uint256[] memory collateralDecimals,
        address usdAddress
    ) USDEngineAbstract(tokenAddresses, priceFeedAddresses, liquidationThresholds, collateralDecimals, usdAddress) {}

    ///////////////////
    // External Functions
    ///////////////////
    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountUSDToMint: The amount of USD you want to mint
     * @notice This function will deposit your collateral and mint USD in one transaction
     */
    function depositCollateralAndMintUsd(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountUsdToMint
    ) external payable override(USDEngineAbstract) {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintUsd(amountUsdToMint, tokenCollateralAddress);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountUSDToBurn: The amount of USD you want to burn
     * @notice This function will withdraw your collateral and burn USD in one transaction
     */
    function redeemCollateralForUsd(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountUsdToBurn
    ) external payable override(USDEngineAbstract) moreThanZero(amountCollateral) {
        _burnUsd(amountUsdToBurn, msg.sender, msg.sender, tokenCollateralAddress);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender, tokenCollateralAddress);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have USD minted, you will not be able to redeem until you burn your USD
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external payable override(USDEngineAbstract) moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender, tokenCollateralAddress);
    }

    /*
     * @notice careful! You'll burn your USD here! Make sure you want to do this...
     * @dev you might want to use this if you're nervous you might get liquidated and want to just burn
     * you USD but keep your collateral in.
     */
    function burnUsd(uint256 amount, address collateral) external override(USDEngineAbstract) moreThanZero(amount) {
        _burnUsd(amount, msg.sender, msg.sender, collateral);
        revertIfHealthFactorIsBroken(msg.sender, collateral);
    }

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your USD to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of USD you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external payable override(USDEngineAbstract) moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user, collateral);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert USDEngine__HealthFactorOk();
        }
        // If covering 100 USD, we need to $100 of collateral
        (uint256 tokenAmountFromDebtCovered, bool isLatestPrice) = getTokenAmountFromUsd(collateral, debtToCover);
        if (!isLatestPrice) {
            revert USDEngine__NotLatestPrice();
        }
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 USD
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
        // Burn USD equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnUsd(debtToCover, user, msg.sender, collateral);

        uint256 endingUserHealthFactor = _healthFactor(user, collateral);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert USDEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender, collateral);
    }

    ///////////////////
    // Public Functions
    ///////////////////
    /*
     * @param amountUSDToMint: The amount of USD you want to mint
     * You can only mint USD if you hav enough collateral
     */
    function mintUsd(uint256 amountUsdToMint, address collateral) public override(USDEngineAbstract) moreThanZero(amountUsdToMint) nonReentrant {
        s_USDMinted[msg.sender][collateral] += amountUsdToMint;
        revertIfHealthFactorIsBroken(msg.sender, collateral);
        bool minted = i_usd.mint(msg.sender, amountUsdToMint);

        if (minted != true) {
            revert USDEngine__MintFailed();
        }
    }

    function getMintableUSD(
        address tokenCollateralAddress,
        address user,
        uint256 amountCollateral
    ) public view override(USDEngineAbstract) returns (uint256, bool) {
        uint256 amount = s_collateralDeposited[user][tokenCollateralAddress];
        uint256 normalizedAmount = normalizeTokenAmount(amountCollateral, tokenCollateralAddress);
        (uint256 usdValue, bool isLatestPrice) = _getUsdValue(tokenCollateralAddress, amount + normalizedAmount);
        uint256 totalUsdMintableAmount = (usdValue * liquidationThreshold[tokenCollateralAddress]) / 100;

        (uint256 totalUsdMinted, , ) = _getAccountInformation(user, tokenCollateralAddress);

        if (totalUsdMintableAmount <= totalUsdMinted) {
            uint256 debtUsdAmount = totalUsdMinted - totalUsdMintableAmount;
            return (debtUsdAmount, false); // cannot mint usd anymore
        } else {
            uint256 mintableUsdAmount = totalUsdMintableAmount - totalUsdMinted;
            return (convertToSafetyValue(mintableUsdAmount), isLatestPrice);
        }
    }

    function getBurnableUSD(
        address tokenCollateralAddress,
        address user,
        uint256 amountUSD
    ) public view override(USDEngineAbstract) returns (uint256, bool) {
        (uint256 totalUsdMinted, uint256 totalCollateralInUSD, ) = _getAccountInformation(user, tokenCollateralAddress);
        uint256 totalUsdAfterBurn = 0;
        uint256 tokenAmountInUSD = 0;
        if (amountUSD < totalUsdMinted) {
            totalUsdAfterBurn = totalUsdMinted - amountUSD;
        }
        uint256 inneedUSDAmount = 0;
        inneedUSDAmount += (totalCollateralInUSD * liquidationThreshold[tokenCollateralAddress]) / 100;

        if (inneedUSDAmount >= totalUsdAfterBurn) {
            tokenAmountInUSD = totalCollateralInUSD;
        } else {
            uint256 backupTokenInUSD = ((totalUsdAfterBurn - inneedUSDAmount) * 100) / liquidationThreshold[tokenCollateralAddress];
            tokenAmountInUSD = totalCollateralInUSD >= backupTokenInUSD ? totalCollateralInUSD - backupTokenInUSD : 0;
        }

        return getTokenAmountFromUsd(tokenCollateralAddress, tokenAmountInUSD);
    }

    //////////////////////////////
    // Private & Internal View & Pure Functions
    //////////////////////////////
    function _getAccountInformation(
        address user,
        address collateral
    ) internal view override(USDEngineAbstract) returns (uint256 totalUsdMinted, uint256 collateralValueInUsd, bool isLatestPrice) {
        totalUsdMinted = s_USDMinted[user][collateral];
        (uint256 _collateralValueInUsd, bool _isLatestPrice) = getAccountCollateralValue(user, collateral);
        collateralValueInUsd = _collateralValueInUsd;
        _isLatestPrice = isLatestPrice;
    }

    function _healthFactor(address user, address collateral) internal view override(USDEngineAbstract) returns (uint256) {
        (uint256 totalUsdMinted, uint256 collateralValueInUsd, bool isLatestPrice) = _getAccountInformation(user, collateral);
        return _calculateHealthFactor(totalUsdMinted, collateralValueInUsd, collateral);
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    // External & Public View & Pure Functions
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    function getAccountCollateralValue(address user, address collateral) public view override(USDEngineAbstract) returns (uint256, bool) {
        uint256 amount = s_collateralDeposited[user][collateral];
        return _getUsdValue(collateral, amount);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view override(USDEngineAbstract) returns (uint256, bool) {
        uint256 tokenAmount;
        bool isLatestPrice;
        if (s_priceFeeds[token] == WSTETHPriceFeed) {
            (uint256 wstETHToEthPrice, bool isLatestPrice1) = validatePriceFeedAndReturnValue(WSTETHPriceFeed);
            (uint256 ethToUSDPrice, bool isLatestPrice2) = validatePriceFeedAndReturnValue(ETHPriceFeed);
            isLatestPrice = isLatestPrice1 && isLatestPrice2;
            tokenAmount = (usdAmountInWei * PRECISION ** 2) / (ADDITIONAL_FEED_PRECISION ** 2 * wstETHToEthPrice * ethToUSDPrice);
        } else {
            (uint256 price, bool _isLatestPrice) = validatePriceFeedAndReturnValue(s_priceFeeds[token]);
            isLatestPrice = _isLatestPrice;
            tokenAmount = ((usdAmountInWei * PRECISION) / (price * ADDITIONAL_FEED_PRECISION));
        }
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        uint256 finalAmount = (tokenAmount * 10 ** s_collateralDecimal[token]) / 10 ** 18;
        return (finalAmount, isLatestPrice);
    }
}

