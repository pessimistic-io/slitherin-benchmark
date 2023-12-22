// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "./TUSDEngineAbstract.sol";

/*
 * Title: USDEngine
 * Author: Torque Inc.
 * Collateral: Exogenous
 * Minting: Algorithmic
 * Stability: TUSD Peg
 * Collateral: Crypto
 *
 * This contract is the core of TUSD.money. It handles the TUSD 'mint
 * and redeem' logic and is based on the MakerDAO DSS system.
 */
contract TUSDEngine is TUSDEngineAbstract {
    ///////////////////
    // Functions
    ///////////////////

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        uint256[] memory liquidationThresholds,
        uint256[] memory collateralDecimals,
        address tusdAddress
    )
        TUSDEngineAbstract(
            tokenAddresses,
            priceFeedAddresses,
            liquidationThresholds,
            collateralDecimals,
            tusdAddress
        )
    {}

    ///////////////////
    // External Functions
    ///////////////////
    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountUSD;ToMint: The amount of TUSD you want to mint
     * @notice This function will deposit your collateral and mint TUSD in one transaction
     */
    function depositCollateralAndMintTusd(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amounUSDToMint,
        address onBehalfUser
    ) external payable override(TUSDEngineAbstract) {
        depositCollateral(tokenCollateralAddress, amountCollateral, onBehalfUser);
        mintTusd(amounUSDToMint, tokenCollateralAddress, onBehalfUser);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountUSD;ToBurn: The amount of TUSD you want to burn
     * @notice This function will withdraw your collateral and burn TUSD in one transaction
     */
    function redeemCollateralForTusd(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountUsdToBurn,
        address onBehalfUser
    ) external payable override(TUSDEngineAbstract) moreThanZero(amountCollateral) {
        _burnUsd(amountUsdToBurn, onBehalfUser, msg.sender, tokenCollateralAddress);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, onBehalfUser, onBehalfUser);
        revertIfHealthFactorIsBroken(onBehalfUser, tokenCollateralAddress);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have TUSD minted, you'll not be able to redeem until you burn your TUSD
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address onBehalfUser
    ) external payable override(TUSDEngineAbstract) moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, onBehalfUser, onBehalfUser);
        revertIfHealthFactorIsBroken(onBehalfUser, tokenCollateralAddress);
    }

    /*
     * @notice You'll burn your TUSD here! Make sure you want to do this..
     * @dev You might want to use this to just to move away from liquidation.
     */
    function burnTusd(
        uint256 amount,
        address collateral,
        address onBehalfUser
    ) external override(TUSDEngineAbstract) moreThanZero(amount) {
        _burnUsd(amount, onBehalfUser, msg.sender, collateral);
        revertIfHealthFactorIsBroken(onBehalfUser, collateral);
    }

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your TUSD to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of TUSD you want to burn to cover the user's debt.
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
    ) external payable override(TUSDEngineAbstract) moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user, collateral);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert TUSDEngine__HealthFactorOk();
        }
        // If covering 100 TUSD, we need to $100 of collateral
        (uint256 tokenAmountFromDebtCovered, bool isLatestPrice) = getTokenAmountFromTusd(
            collateral,
            debtToCover
        );
        if (!isLatestPrice) {
            revert TUSDEngine__NotLatestPrice();
        }
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 TUSD
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
        // Burn TUSD equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        _redeemCollateral(
            collateral,
            tokenAmountFromDebtCovered + bonusCollateral,
            user,
            msg.sender
        );
        _burnUsd(debtToCover, user, msg.sender, collateral);

        uint256 endingUserHealthFactor = _healthFactor(user, collateral);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert TUSDEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender, collateral);
    }

    ///////////////////
    // Public Functions
    ///////////////////
    /*
     * @param amountUSD;ToMint: The amount of TUSD you want to mint
     * You can only mint TUSD if you have enough collateral
     */
    function mintTusd(
        uint256 amounUSDToMint,
        address collateral,
        address onBehalfUser
    ) public override(TUSDEngineAbstract) moreThanZero(amounUSDToMint) nonReentrant {
        s_USDMinted[onBehalfUser][collateral] += amounUSDToMint;
        revertIfHealthFactorIsBroken(onBehalfUser, collateral);
        bool minted = i_usd.mint(msg.sender, amounUSDToMint);

        if (minted != true) {
            revert TUSDEngine__MintFailed();
        }
    }

    function getMintableTUSD(
        address tokenCollateralAddress,
        address user,
        uint256 amountCollateral
    ) public view override(TUSDEngineAbstract) returns (uint256, bool) {
        uint256 amount = s_collateralDeposited[user][tokenCollateralAddress];
        uint256 normalizedAmount = normalizeTokenAmount(amountCollateral, tokenCollateralAddress);
        (uint256 tusdValue, bool isLatestPrice) = _getTusdValue(
            tokenCollateralAddress,
            amount + normalizedAmount
        );
        uint256 totalTusdMintableAmount = (tusdValue *
            liquidationThreshold[tokenCollateralAddress]) / 100;

        (uint256 totalUsdMinted, , ) = _getAccountInformation(user, tokenCollateralAddress);

        if (totalTusdMintableAmount <= totalUsdMinted) {
            uint256 debtTusdAmount = totalUsdMinted - totalTusdMintableAmount;
            return (debtTusdAmount, false); // cannot mint tusd anymore
        } else {
            uint256 mintableTusdAmount = totalTusdMintableAmount - totalUsdMinted;
            return (convertToSafetyValue(mintableTusdAmount), isLatestPrice);
        }
    }

    function getBurnableTUSD(
        address tokenCollateralAddress,
        address user,
        uint256 amountUSD
    ) public view override(TUSDEngineAbstract) returns (uint256, bool) {
        (uint256 totalUsdMinted, uint256 totalCollateralInUSD, ) = _getAccountInformation(
            user,
            tokenCollateralAddress
        );
        uint256 totalTusdAfterBurn = 0;
        uint256 tokenAmountInTUSD = 0;
        if (amountUSD < totalUsdMinted) {
            totalTusdAfterBurn = totalUsdMinted - amountUSD;
        }
        uint256 inneedTUSDAmount = 0;
        inneedTUSDAmount +=
            (totalCollateralInUSD * liquidationThreshold[tokenCollateralAddress]) /
            100;

        if (inneedTUSDAmount >= totalTusdAfterBurn) {
            tokenAmountInTUSD = totalCollateralInUSD;
        } else {
            uint256 backupTokenInTUSD = ((totalTusdAfterBurn - inneedTUSDAmount) * 100) /
                liquidationThreshold[tokenCollateralAddress];
            tokenAmountInTUSD = totalCollateralInUSD >= backupTokenInTUSD
                ? totalCollateralInUSD - backupTokenInTUSD
                : 0;
        }

        return getTokenAmountFromTusd(tokenCollateralAddress, tokenAmountInTUSD);
    }

    //////////////////////////////
    // Private & Internal View & Pure Functions
    //////////////////////////////
    function _getAccountInformation(
        address user,
        address collateral
    )
        internal
        view
        override(TUSDEngineAbstract)
        returns (uint256 totalUsdMinted, uint256 collateralValueInUsd, bool isLatestPrice)
    {
        totalUsdMinted = s_USDMinted[user][collateral];
        (uint256 _collateralValueInUsd, bool _isLatestPrice) = getAccountCollateralValue(
            user,
            collateral
        );
        collateralValueInUsd = _collateralValueInUsd;
        _isLatestPrice = isLatestPrice;
    }

    function _healthFactor(
        address user,
        address collateral
    ) internal view override(TUSDEngineAbstract) returns (uint256) {
        (
            uint256 totalUsdMinted,
            uint256 collateralValueInUsd,
            bool isLatestPrice
        ) = _getAccountInformation(user, collateral);
        return _calculateHealthFactor(totalUsdMinted, collateralValueInUsd, collateral);
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    // External & Public View & Pure Functions
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    function getAccountCollateralValue(
        address user,
        address collateral
    ) public view override(TUSDEngineAbstract) returns (uint256, bool) {
        uint256 amount = s_collateralDeposited[user][collateral];
        return _getTusdValue(collateral, amount);
    }

    function getTokenAmountFromTusd(
        address token,
        uint256 usdAmountInWei
    ) public view override(TUSDEngineAbstract) returns (uint256, bool) {
        uint256 tokenAmount;
        bool isLatestPrice;
        if (s_priceFeeds[token] == WSTETHPriceFeed) {
            (uint256 wstETHToEthPrice, bool isLatestPrice1) = validatePriceFeedAndReturnValue(
                WSTETHPriceFeed
            );
            (uint256 ethToTUSDPrice, bool isLatestPrice2) = validatePriceFeedAndReturnValue(
                ETHPriceFeed
            );
            isLatestPrice = isLatestPrice1 && isLatestPrice2;
            tokenAmount =
                (usdAmountInWei * PRECISION ** 2) /
                (ADDITIONAL_FEED_PRECISION ** 2 * wstETHToEthPrice * ethToTUSDPrice);
        } else {
            (uint256 price, bool _isLatestPrice) = validatePriceFeedAndReturnValue(
                s_priceFeeds[token]
            );
            isLatestPrice = _isLatestPrice;
            tokenAmount = ((usdAmountInWei * PRECISION) / (price * ADDITIONAL_FEED_PRECISION));
        }
        uint256 finalAmount = (tokenAmount * 10 ** s_collateralDecimal[token]) / 10 ** 18;
        return (finalAmount, isLatestPrice);
    }
}

