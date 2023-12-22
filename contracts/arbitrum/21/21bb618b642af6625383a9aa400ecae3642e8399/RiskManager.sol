// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./RiskManagerStorage.sol";
import "./Initializable.sol";
import "./ITokenBase.sol";
import "./IRiskManager.sol";
import "./IPriceOracle.sol";
import "./IERC20Upgradeable.sol";

contract RiskManager is Initializable, RiskManagerStorage, IRiskManager {
    function initialize(address _priceOracle) public initializer {
        admin = msg.sender;

        liquidationIncentiveMantissa = 1.1e18;

        boostIncreaseMantissa = 1e15;
        boostRequiredToken = 1000000e18;

        oracle = IPriceOracle(_priceOracle);
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "RiskManager: Not authorized to call");
        _;
    }

    modifier onlyListed(address _fToken) {
        require(markets[_fToken].isListed, "RiskManager: Market is not listed");
        _;
    }

    function isRiskManager() public pure returns (bool) {
        return IS_RISK_MANAGER;
    }

    /**
     * @dev Returns the markets an account has entered.
     */
    function getMarketsEntered(
        address _account
    ) external view returns (address[] memory) {
        // getAssetsIn
        address[] memory entered = marketsEntered[_account]; // accountAssets[]

        return entered;
    }

    function getMarketInfo(
        address _ftoken
    ) external view returns (uint256, uint256) {
        return (
            markets[_ftoken].collateralFactorMantissa,
            markets[_ftoken].liquidationFactorMantissa
        );
    }

    /**
     * @dev Check if the given account has entered in the given asset.
     */
    function checkMembership(
        address _account,
        address _fToken
    ) external view returns (bool) {
        return markets[_fToken].isMember[_account];
    }

    function checkListed(address _fToken) external view returns (bool) {
        return markets[_fToken].isListed;
    }

    function setLeverageContract(address _furionLeverage) external onlyAdmin {
        furionLeverage = _furionLeverage;
    }

    /**
     * @dev Add assets to be included in account liquidity calculation
     */
    function enterMarkets(address[] memory _fTokens) public override {
        uint256 len = _fTokens.length;

        for (uint256 i; i < len; ) {
            addToMarketInternal(_fTokens[i], msg.sender);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Add the asset for liquidity calculations of borrower
     */
    function addToMarketInternal(
        address _fToken,
        address _borrower
    ) internal onlyListed(_fToken) {
        Market storage marketToJoin = markets[_fToken];

        if (marketToJoin.isMember[_borrower] == true) {
            return;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.isMember[_borrower] = true;
        marketsEntered[_borrower].push(_fToken);

        emit MarketEntered(_fToken, _borrower);
    }

    /**
     * @dev Removes asset from sender's account liquidity calculation.
     *
     * Sender must not have an outstanding borrow balance in the asset,
     * or be providing necessary collateral for an outstanding borrow.
     */
    function exitMarket(address _fToken) external override {
        /// Get fToken balance and amount of underlying asset borrowed
        (uint256 tokensHeld, uint256 amountOwed, ) = ITokenBase(_fToken)
            .getAccountSnapshot(msg.sender);
        // Fail if the sender has a borrow balance
        require(amountOwed == 0, "RiskManager: Borrow balance is not zero");

        // Fail if the sender is not permitted to redeem all of their tokens
        require(
            redeemAllowed(_fToken, msg.sender, tokensHeld),
            "RiskManager: Cannot withdraw all tokens"
        );

        Market storage marketToExit = markets[_fToken];

        // Already exited market
        if (!marketToExit.isMember[msg.sender]) {
            return;
        }

        // Set fToken membership to false
        delete marketToExit.isMember[msg.sender];

        // Delete fToken from the account’s list of assets
        // load into memory for faster iteration
        address[] memory assets = marketsEntered[msg.sender];
        uint256 len = assets.length;
        uint256 assetIndex;
        for (uint256 i; i < len; i++) {
            if (assets[i] == _fToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // Copy last item in list to location of item to be removed, reduce length by 1
        address[] storage storedList = marketsEntered[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(_fToken, msg.sender);
    }

    /********************************* Admin *********************************/

    /**
     * @notice Begins transfer of admin rights. The newPendingAdmin MUST call
     *  `acceptAdmin` to finalize the transfer.
     * @dev Admin function to begin change of admin. The newPendingAdmin MUST
     *  call `acceptAdmin` to finalize the transfer.
     * @param _newPendingAdmin New pending admin.
     */
    function setPendingAdmin(address _newPendingAdmin) external onlyAdmin {
        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;

        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = _newPendingAdmin;

        // Emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin)
        emit NewPendingAdmin(oldPendingAdmin, _newPendingAdmin);
    }

    /**
     * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
     * @dev Admin function for pending admin to accept role and update admin
     */
    function acceptAdmin() external {
        // Check caller is pendingAdmin
        require(msg.sender == pendingAdmin, "TokenBase: Not pending admin");

        // Save current values for inclusion in log
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = address(0);

        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
    }

    /**
     * @notice Sets a new price oracle for the comptroller
     * @dev Admin function to set a new price oracle
     */
    function setPriceOracle(address _newOracle) external onlyAdmin {
        // Track the old oracle for the comptroller
        address oldOracle = address(oracle);

        // Set comptroller's oracle to newOracle
        oracle = IPriceOracle(_newOracle);

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, _newOracle);
    }

    function setVeToken(address _newVeToken) external onlyAdmin {
        emit NewVeToken(address(veToken), _newVeToken);

        veToken = IERC20(_newVeToken);
    }

    function setCloseFactor(
        uint256 _newCloseFactorMantissa
    ) external onlyAdmin {
        require(
            _newCloseFactorMantissa >= CLOSE_FACTOR_MIN_MANTISSA &&
                _newCloseFactorMantissa <= CLOSE_FACTOR_MAX_MANTISSA,
            "RiskManager: Close factor not within limit"
        );

        uint256 oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = _newCloseFactorMantissa;

        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);
    }

    /**
     * @notice Sets the collateralFactor for a market
     * @dev Admin function to set per-market collateralFactor
     * @param _fToken The market to set the factor on
     * @param _newCollateralFactorMantissa The new collateral factor, scaled by 1e18
     */
    function setCollateralFactor(
        address _fToken,
        uint256 _newCollateralFactorMantissa
    ) external onlyAdmin onlyListed(_fToken) {
        // Check collateral factor <= 0.9
        require(
            _newCollateralFactorMantissa <= COLLATERAL_FACTOR_MAX_MANTISSA,
            "RiskManager: Collateral factor larger than limit"
        );

        // Fail if price == 0
        uint256 price = oracle.getUnderlyingPrice(_fToken);
        require(price > 0, "RiskManager: Oracle price is 0");

        Market storage market = markets[_fToken];
        // Set market's collateral factor to new collateral factor, remember old value
        uint256 oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = _newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(
            _fToken,
            oldCollateralFactorMantissa,
            _newCollateralFactorMantissa
        );
    }

    function setLiquidationFactor(
        address _fToken,
        uint256 _newLiquidationFactorMantissa
    ) external onlyAdmin onlyListed(_fToken) {
        require(
            _newLiquidationFactorMantissa <= LIQUIDATION_FACTOR_MAX_MANTISSA,
            "RiskManager: Liquidation factor larger than limit"
        );

        Market storage market = markets[_fToken];
        uint256 oldLiquidationFactorMantissa = market.liquidationFactorMantissa;
        market.liquidationFactorMantissa = _newLiquidationFactorMantissa;

        emit NewLiquidationFactor(
            _fToken,
            oldLiquidationFactorMantissa,
            _newLiquidationFactorMantissa
        );
    }

    function setLiquidationIncentive(uint256 _newIncentiveMantissa) external onlyAdmin {
        emit NewLiquidationIncentive(liquidationIncentiveMantissa, _newIncentiveMantissa);

        liquidationIncentiveMantissa = _newIncentiveMantissa;
    }

    function setBoostIncrease(uint256 _newIncreaseMantissa) external onlyAdmin {
        emit NewBoostIncrease(boostIncreaseMantissa, _newIncreaseMantissa);

        boostIncreaseMantissa = _newIncreaseMantissa;
    }

    function setBoostRequired(uint256 _newRequired) external onlyAdmin {
        emit NewBoostRequired(boostRequiredToken, _newRequired);

        boostRequiredToken = _newRequired;
    }

    /**
     * @notice Add the market to the markets mapping and set it as listed
     * @dev Admin function to set isListed and add support for the market
     * @param _fToken The address of the market (token) to list
     */
    function supportMarket(
        address _fToken,
        uint256 _collateralFactorMantissa,
        uint256 _liquidationFactorMantissa
    ) external onlyAdmin {
        require(
            !markets[_fToken].isListed,
            "RiskManager: Market already listed"
        );
        require(
            _collateralFactorMantissa <= COLLATERAL_FACTOR_MAX_MANTISSA,
            "RiskManager: Invalid collateral factor"
        );
        require(
            _liquidationFactorMantissa >= _collateralFactorMantissa &&
                _liquidationFactorMantissa <= LIQUIDATION_FACTOR_MAX_MANTISSA,
            "RiskManager: Invalid liquidation factor"
        );

        ITokenBase(_fToken).isFToken(); // Sanity check to make sure its really a FToken

        Market storage newMarket = markets[_fToken];
        newMarket.isListed = true;
        newMarket.collateralFactorMantissa = _collateralFactorMantissa;
        newMarket.liquidationFactorMantissa = _liquidationFactorMantissa;

        emit MarketListed(_fToken);
    }

    function setSupplyPaused(
        address _fToken,
        bool _state
    ) external onlyListed(_fToken) onlyAdmin returns (bool) {
        supplyGuardianPaused[_fToken] = _state;
        emit ActionPausedMarket(_fToken, "Supply", _state);
        return _state;
    }

    function setBorrowPaused(
        address _fToken,
        bool _state
    ) external onlyListed(_fToken) onlyAdmin returns (bool) {
        borrowGuardianPaused[_fToken] = _state;
        emit ActionPausedMarket(_fToken, "Borrow", _state);
        return _state;
    }

    function setTransferPaused(bool _state) external onlyAdmin returns (bool) {
        transferGuardianPaused = _state;
        emit ActionPausedGlobal("Transfer", _state);
        return _state;
    }

    function setSeizePaused(bool _state) external onlyAdmin returns (bool) {
        seizeGuardianPaused = _state;
        emit ActionPausedGlobal("Seize", _state);
        return _state;
    }

    /********************************* Hooks *********************************/

    /**
     * NOTE: Although the hooks are free to call externally, it is important to
     * note that they may not be accurate when called externally by non-Furion
     * contracts because accrueInterest() is not called and lastAccrualBlock may
     * not be the same as current block number. In other words, market state may
     * not be up-to-date.
     */

    /**
     * @dev Checks if the account should be allowed to supply tokens in the given market.
     */
    function supplyAllowed(
        address _fToken
    ) external view onlyListed(_fToken) returns (bool) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(
            !supplyGuardianPaused[_fToken],
            "RiskManager: Supplying is paused"
        );

        return true;
    }

    /**
     * @dev Checks if the account should be allowed to redeem fTokens for underlying
     *  asset in the given market, i.e. check if it will create shortfall / a shortfall
     *  already exists
     * @param _redeemTokens Amount of fTokens used for redemption.
     */
    function redeemAllowed(
        address _fToken,
        address _redeemer,
        uint256 _redeemTokens
    ) public view onlyListed(_fToken) returns (bool) {
        // Can freely redeem if redeemer never entered market, as liquidity calculation is not affected
        if (!markets[_fToken].isMember[_redeemer]) {
            return true;
        }

        // Otherwise, perform a hypothetical liquidity check to guard against shortfall
        (, uint256 shortfall, , ) = getHypotheticalAccountLiquidity(
            _redeemer,
            _fToken,
            _redeemTokens,
            0
        );
        require(shortfall == 0, "RiskManager: Insufficient liquidity");

        return true;
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying
     *  asset of the given market.
     * @param _fToken The market to verify the borrow against.
     * @param _borrower The account which would borrow the asset.
     * @param _borrowAmount The amount of underlying the account would borrow.
     */
    function borrowAllowed(
        address _fToken,
        address _borrower,
        uint256 _borrowAmount
    ) external override onlyListed(_fToken) returns (bool) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(
            !borrowGuardianPaused[_fToken],
            "RiskManager: Borrow is paused"
        );

        if (!markets[_fToken].isMember[_borrower]) {
            // only fToken contract may call borrowAllowed if borrower not in market
            require(
                msg.sender == _fToken,
                "RiskManager: Sender must be fToken contract"
            );

            // attempt to add borrower to the market
            addToMarketInternal(_fToken, _borrower);

            // it should be impossible to break the important invariant
            assert(markets[_fToken].isMember[_borrower]);
        }

        uint256 price = oracle.getUnderlyingPrice(_fToken);
        require(price > 0, "RiskManager: Oracle price is 0");

        (, uint256 shortfall, , ) = getHypotheticalAccountLiquidity(
            _borrower,
            _fToken,
            0,
            _borrowAmount
        );
        require(
            shortfall == 0,
            "RiskManager: Shortfall created, cannot borrow"
        );

        return true;
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the
     *  given market (if a market is listed)
     * @param _fToken The market to verify the repay against
     */
    function repayBorrowAllowed(
        address _fToken
    ) external view onlyListed(_fToken) returns (bool) {
        return true;
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param _fTokenBorrowed Asset which was borrowed by the borrower
     * @param _fTokenCollateral Asset which was used as collateral and will be seized
     * @param _borrower The address of the borrower
     * @param _repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address _fTokenBorrowed,
        address _fTokenCollateral,
        address _borrower,
        uint256 _repayAmount
    ) external view returns (bool) {
        require(
            markets[_fTokenBorrowed].isListed &&
                markets[_fTokenCollateral].isListed,
            "RiskManager: Market is not listed"
        );

        // Stored version used because accrueInterest() has been called at the
        // beginning of liquidateBorrowInternal()
        uint256 borrowBalance = ITokenBase(_fTokenBorrowed)
            .borrowBalanceCurrent(_borrower);

        (, , uint256 shortfall, ) = getAccountLiquidity(_borrower);
        // The borrower must have shortfall in order to be liquidatable
        require(shortfall > 0, "RiskManager: Insufficient shortfall");

        // The liquidator may not repay more than what is allowed by the closeFactor
        uint256 maxClose = mul_ScalarTruncate(
            Exp({mantissa: closeFactorMantissa}),
            borrowBalance
        );

        require(maxClose >= _repayAmount, "RiskManager: Repay too much");

        return true;
    }

    function delegateLiquidateBorrowAllowed(
        address _fTokenBorrowed,
        address _fTokenCollateral,
        address _borrower,
        uint256 _repayAmount
    ) external view returns (bool) {
        require(
            markets[_fTokenBorrowed].isListed &&
                markets[_fTokenCollateral].isListed,
            "RiskManager: Market is not listed"
        );

        // Stored version used because accrueInterest() has been called at the
        // beginning of liquidateBorrowInternal()
        uint256 borrowBalance = ITokenBase(_fTokenBorrowed)
            .borrowBalanceCurrent(_borrower);

        (, , uint256 shortfall, ) = getAccountLiquidity(_borrower);
        // The borrower must have shortfall in order to be liquidatable
        require(shortfall > 0, "RiskManager: Insufficient shortfall");
        require(borrowBalance >= _repayAmount, "RiskManager: Repay too much");
        return true;
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param _fTokenCollateral Asset which was used as collateral and will be seized
     * @param _fTokenBorrowed Asset which was borrowed by the borrower
     * @param _borrower The address of the borrower
     */
    function seizeAllowed(
        address _fTokenCollateral,
        address _fTokenBorrowed,
        address _borrower,
        uint256 _seizeTokens
    ) external view returns (bool allowed) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "RiskManager: Seize is paused");

        // Revert if borrower collateral token balance < seizeTokens
        require(
            IERC20Upgradeable(_fTokenCollateral).balanceOf(_borrower) >=
                _seizeTokens,
            "RiskManager: Seize token amount exceeds collateral"
        );

        require(
            markets[_fTokenBorrowed].isListed &&
                markets[_fTokenCollateral].isListed,
            "RiskManager: Market is not listed"
        );

        require(
            ITokenBase(_fTokenCollateral).getRiskManager() ==
                ITokenBase(_fTokenBorrowed).getRiskManager(),
            "RiskManager: Risk manager mismatch"
        );

        allowed = true;
    }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param _fToken The market to verify the transfer against
     * @param _src The account which sources the tokens
     * @param _amount The number of fTokens to transfer
     */
    function transferAllowed(
        address _fToken,
        address _src,
        uint256 _amount
    ) external view returns (bool) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!transferGuardianPaused, "transfer is paused");

        // Currently the only consideration is whether or not
        // the src is allowed to redeem this many tokens
        require(
            redeemAllowed(_fToken, _src, _amount),
            "RiskManager: Source not allowed to redeem that much fTokens"
        );

        return true;
    }

    /****************************** Liquidation *******************************/

    function collateralFactorBoost(
        address _account
    ) public view returns (uint256 boostMantissa) {
        if (address(veToken) == address(0)) return 0;

        uint256 veBalance = veToken.balanceOf(_account);
        // How many 0.1% the collateral factor will be increased by.
        // Result is rounded down by default which is fine
        uint256 multiplier = veBalance / boostRequiredToken;

        boostMantissa = boostIncreaseMantissa * multiplier;

        if (boostMantissa > COLLATERAL_FACTOR_MAX_BOOST_MANTISSA) {
            boostMantissa = COLLATERAL_FACTOR_MAX_BOOST_MANTISSA;
        }
    }

    /**
     * @notice Determine the current account liquidity wrt collateral & liquidation requirements
     * @return liquidity Hypothetical spare liquidity
     * @return shortfallCollateral Hypothetical account shortfall below collateral requirements,
     *         used for determining if borrowing/redeeming is allowed
     * @return shortfallLiquidation Hypothetical account shortfall below liquidation requirements,
     *         used for determining if liquidation is allowed
     * @return healthFactor Health factor of account scaled by 1e18, 0 if the account has no borrowings
     */
    function getAccountLiquidity(
        address _account
    )
        public
        view
        returns (
            uint256 liquidity,
            uint256 shortfallCollateral,
            uint256 shortfallLiquidation,
            uint256 healthFactor
        )
    {
        // address(0) -> no iteractions with market
        (
            liquidity,
            shortfallCollateral,
            shortfallLiquidation,
            healthFactor
        ) = getHypotheticalAccountLiquidity(_account, address(0), 0, 0);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts
     *  were redeemed/borrowed
     * @param _account The account to determine liquidity for
     * @param _fToken The market to hypothetically redeem/borrow in
     * @param _redeemToken The number of fTokens to hypothetically redeem
     * @param _borrowAmount The amount of underlying to hypothetically borrow
     * @return liquidity Hypothetical spare liquidity
     * @return shortfallCollateral Hypothetical account shortfall below collateral requirements,
     *         used for determining if borrowing/redeeming is allowed
     * @return shortfallLiquidation Hypothetical account shortfall below liquidation requirements,
     *         used for determining if liquidation is allowed
     * @return healthFactor Health factor of account scaled by 1e18, used only for off-chain operations.
     *         Return only if querying without interaction, i.e. getAccountLiquidity(), 0 (invalid) otherwise.
     *         Account without any borrowings will also have a health factor of 0
     */
    function getHypotheticalAccountLiquidity(
        address _account,
        address _fToken,
        uint256 _redeemToken,
        uint256 _borrowAmount
    )
        public
        view
        returns (
            uint256 liquidity,
            uint256 shortfallCollateral,
            uint256 shortfallLiquidation,
            uint256 healthFactor
        )
    {
        // Holds all our calculation results, see { RiskManagerStorage }
        AccountLiquidityLocalVars memory vars;

        // For each asset the account is in
        // Loop through to calculate total collateral and borrowed values
        address[] memory assets = marketsEntered[_account];
        for (uint256 i; i < assets.length; ) {
            vars.asset = assets[i];

            // Read the balances and exchange rate from the asset (market)
            (
                vars.tokenBalance,
                vars.borrowBalance,
                vars.exchangeRateMantissa
            ) = ITokenBase(vars.asset).getAccountSnapshot(_account);

            vars.collateralFactor = Exp({
                mantissa: markets[vars.asset].collateralFactorMantissa +
                    collateralFactorBoost(_account)
            });
            vars.liquidationFactor = Exp({
                mantissa: markets[vars.asset].liquidationFactorMantissa
            });

            // Decimal: underlying + 18 - fToken
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the underlying asset of fToken
            vars.oraclePriceMantissa = oracle.getUnderlyingPrice(vars.asset);
            require(
                vars.oraclePriceMantissa > 0,
                "RiskManager: Oracle price is 0"
            );
            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            vars.valuePerToken = mul_(vars.oraclePrice, vars.exchangeRate);
            vars.collateralValuePerToken = mul_(
                vars.valuePerToken,
                vars.collateralFactor
            );
            vars.liquidationValuePerToken = mul_(
                vars.valuePerToken,
                vars.liquidationFactor
            );

            /** @dev All these are compared with decimal point of 18
             *       Decimal: underlying + 18 - fToken [exchange rate]
             *                + 36 - underlying [oracle price] - 18 [Exp mul]
             *                + 18 [collateral/liquidation factor] - 18 [Exp mul]
             *                + fToken [token balance] - 18 [Exp mul]
             *                = 18
             */
            vars.sumCollateral = mul_ScalarTruncateAddUInt(
                vars.collateralValuePerToken,
                vars.tokenBalance,
                vars.sumCollateral
            );
            // Decimal: same as sumCollateral
            vars.liquidationThreshold = mul_ScalarTruncateAddUInt(
                vars.liquidationValuePerToken,
                vars.tokenBalance,
                vars.liquidationThreshold
            );
            // Decimal: 36 - underlying [oracle price] + underlying [borrow balance] - 18 [Exp mul] = 18
            vars.sumBorrowPlusEffect = mul_ScalarTruncateAddUInt(
                vars.oraclePrice,
                vars.borrowBalance,
                vars.sumBorrowPlusEffect
            );
            vars.sumBorrowPlusEffectLiquidation = vars.sumBorrowPlusEffect;

            // Calculate effects of interacting with fToken
            if (vars.asset == _fToken) {
                // Redeem effect
                // Collateral reduced same as collateral unchanged but borrow increased
                vars.sumBorrowPlusEffect = mul_ScalarTruncateAddUInt(
                    vars.collateralValuePerToken,
                    _redeemToken,
                    vars.sumBorrowPlusEffect
                );
                vars.sumBorrowPlusEffectLiquidation = mul_ScalarTruncateAddUInt(
                    vars.liquidationValuePerToken,
                    _redeemToken,
                    vars.sumBorrowPlusEffectLiquidation
                );

                // Add amount to hypothetically borrow
                // Borrow increased after borrowing
                vars.sumBorrowPlusEffect = mul_ScalarTruncateAddUInt(
                    vars.oraclePrice,
                    _borrowAmount,
                    vars.sumBorrowPlusEffect
                );
            }

            unchecked {
                ++i;
            }
        }

        // sumBorrowPlusEffectLiquidation is always greater than sumBorrowPlusEffect due to a larger factor
        if (vars.sumCollateral > vars.sumBorrowPlusEffect) {
            liquidity = vars.sumCollateral - vars.sumBorrowPlusEffect;
            shortfallCollateral = 0;
            shortfallLiquidation = 0;
        } else {
            liquidity = 0;
            shortfallCollateral = vars.sumBorrowPlusEffect - vars.sumCollateral;
            shortfallLiquidation = vars.sumBorrowPlusEffectLiquidation >
                vars.liquidationThreshold
                ? (vars.sumBorrowPlusEffectLiquidation -
                    vars.liquidationThreshold)
                : 0;
        }

        // Return health factor only for queries without interaction, i.e. invoked through getAccountLiquidity()
        if (_fToken == address(0) && vars.sumBorrowPlusEffect != 0)
            healthFactor = div_(
                vars.liquidationThreshold,
                Exp({mantissa: vars.sumBorrowPlusEffect})
            );
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in fToken.liquidateBorrowInternal)
     * @param _fTokenBorrowed The address of the borrowed cToken
     * @param _fTokenCollateral The address of the collateral cToken
     * @param _repayAmount The amount of fTokenBorrowed underlying to convert into fTokenCollateral tokens
     * @return seizeTokens Number of fTokenCollateral tokens to be seized in a liquidation
     */
    function liquidateCalculateSeizeTokens(
        address _fTokenBorrowed,
        address _fTokenCollateral,
        uint256 _repayAmount
    ) external view override returns (uint256 seizeTokens) {
        // Read oracle prices for borrowed and collateral markets
        uint256 priceBorrowedMantissa = oracle.getUnderlyingPrice(
            _fTokenBorrowed
        );
        uint256 priceCollateralMantissa = oracle.getUnderlyingPrice(
            _fTokenCollateral
        );
        require(
            priceBorrowedMantissa > 0 && priceCollateralMantissa > 0,
            "RiskManager: Oracle price is 0"
        );

        // Decimal: underlying + 18 - fToken
        uint256 exchangeRateMantissa = ITokenBase(_fTokenCollateral)
            .exchangeRateCurrent();

        /**
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = (actualRepayAmount * liquidationIncentive) * priceBorrowed / (priceCollateral * exchangeRate)
         */

        // Decimal: 18 [incentive] + underlying
        Exp memory amountAfterDiscount = mul_(
            Exp({mantissa: liquidationIncentiveMantissa}),
            _repayAmount
        );

        // Decimal: amountAfterDiscount + 36 - underlying [price oracle] - 18 [Exp mul] - 18 [truncate]
        //          = 18
        uint256 valueAfterDiscount = truncate(
            mul_(amountAfterDiscount, Exp({mantissa: priceBorrowedMantissa}))
        );

        /**   (value / underyling) * exchangeRate
         *  = (value /underlying) * (underlying / token)
         *  = value per token
         */

        // Decimal: 36 - underlying [price oracle] + (underlying + 18 - fToken) [exchange rate] - 18 [Exp mul]
        //          = 36 - fToken
        Exp memory valuePerToken = mul_(
            Exp({mantissa: priceCollateralMantissa}),
            Exp({mantissa: exchangeRateMantissa})
        );

        // Decimal: valueAfterDiscount + 18 [Exp div] - valuePerToken
        //          = 18 + 18 - (36 - fToken)
        //          = fToken
        seizeTokens = div_(valueAfterDiscount, valuePerToken);
    }
}

