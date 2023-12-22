//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import {IPositionRouter} from "./IPositionRouter.sol";
import {IVaultPriceFeed} from "./IVaultPriceFeed.sol";
import {IReader} from "./IReader.sol";
import {IVault} from "./IVault.sol";
import {IAtlanticPutsPool} from "./IAtlanticPutsPool.sol";
import {IInsuredLongsStrategy} from "./IInsuredLongsStrategy.sol";
import {IDopexPositionManager} from "./IDopexPositionManager.sol";
import {IERC20} from "./IERC20.sol";
import {OptionsPurchase} from "./AtlanticsStructs.sol";

contract InsuredLongsUtils {
    address private owner;

    IVault public vault;
    IPositionRouter public positionRouter;
    IReader public reader;

    uint256 private constant USDG_DECIMALS = 30;
    uint256 private constant STRIKE_DECIMALS = 8;
    uint256 private constant OPTIONS_TOKEN_DECIMALS = 18;
    uint256 private constant BPS_PRECISION = 100000;
    uint256 private constant SWAP_BPS_PRECISION = 10000;
    uint256 private feebufferBps = 5;

    event NewOwnerSet(address _newOwner, address _olderOwner);

    constructor() {
        owner = msg.sender;
    }

    function setOwner(address _newOwner) external onlyOwner {
        owner = _newOwner;
        emit NewOwnerSet(_newOwner, msg.sender);
    }

    function setAddresses(
        address _vault,
        address _positionRouter,
        address _reader
    ) external onlyOwner {
        vault = IVault(_vault);
        positionRouter = IPositionRouter(_positionRouter);
        reader = IReader(_reader);
    }

    /**
     * @notice Get leverage of a existing position on GMX.
     * @param _positionManager Address of the position manager
     *                         delegating the user.
     * @param _indexToken      Address of the index token of
     *                         the long position.
     * @return _positionLeverage
     */
    function getPositionLeverage(
        address _positionManager,
        address _indexToken
    ) public view returns (uint256 _positionLeverage) {
        return
            vault.getPositionLeverage(
                _positionManager,
                _indexToken,
                _indexToken,
                true
            );
    }

    /**
     * @notice Calculate leverage from collateral and size.
     * @param _collateralToken Address of the collateral token or input
     *                         token.
     * @param _indexToken      Address of the index token longing on.
     * @param _collateralDelta  Amount of collateral in collateral token decimals.
     * @param _sizeDelta        Size of the position usd in 1e30 decimals.
     * @return _positionLeverage
     */
    function getPositionLeverage(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta
    ) public view returns (uint256 _positionLeverage) {
        _positionLeverage =
            ((_sizeDelta * 1e30) /
                calculateCollateral(
                    _collateralToken,
                    _indexToken,
                    _collateralDelta,
                    _sizeDelta
                )) /
            1e26;
    }

    /**
     * @notice Calculate leverage using collateral and size.
     *         Note that this is an approximate amount and does
     *         not consider fees.
     * @param _size            Size of the position in 1e30 usd decimals
     * @param _collateral      Collateral amount of the position in its own
     *                         token decimals.
     * @param _collateralToken Address of the collateral token.
     * @return _leverage
     */
    function calculateLeverage(
        uint256 _size,
        uint256 _collateral,
        address _collateralToken
    ) external view returns (uint256 _leverage) {
        return
            ((_size * 10 ** (USDG_DECIMALS)) /
                vault.tokenToUsdMin(_collateralToken, _collateral)) /
            10 ** (USDG_DECIMALS - 4);
    }

    /**
     * @notice Gets the liquidation price of a existing GMX position.
     *         Sums up the usd value of the collateral, position fee,
     *         funding fee and liquidation fee that needs to be depleted
     *         first to get liquidated. Note that this is an slightly
     *         approximate value as GMX looks for other different conditions
     *         before liquidating a position but this return fn ensures it
     *         returns a safer value considering all fees.
     * @param _positionManager Address of the position manager
     *                         delegating the user.
     * @param _indexToken      Address of the index token of
     *                         the long position.
     * @return liquidationPrice
     */
    function getLiquidationPrice(
        address _positionManager,
        address _indexToken
    ) public view returns (uint256 liquidationPrice) {
        (uint256 size, uint256 collateral, uint256 entryPrice, , , , , ) = vault
            .getPosition(_positionManager, _indexToken, _indexToken, true);

        uint256 fees = getFundingFee(
            _indexToken,
            _positionManager,
            address(0)
        ) +
            getPositionFee(size) +
            vault.liquidationFeeUsd();

        uint256 priceDelta = ((collateral - fees) * entryPrice) / size;
        liquidationPrice = entryPrice - priceDelta;
    }

    /**
     * @notice Calculate liquidation price from collateral delta
     *         and size delta. considers position fee and liquidation
     *         fee. note that this does not consider funding fees
     *         and should be used to fetch a pre-determined liquidation
     *         price.
     * @param _collateralToken  Address of the input token or collateral token.
     * @param _indexToken       Address of the index token to long for.
     * @param _collateralDelta  Amount of collateral in collateral token decimals.
     * @param _sizeDelta        Size of the position usd in 1e30 decimals.
     * @return liquidationPrice
     */
    function getLiquidationPrice(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta
    ) public view returns (uint256 liquidationPrice) {
        uint256 entryPrice = vault.getMaxPrice(_indexToken);
        _collateralDelta = calculateCollateral(
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta
        );
        uint256 fees = (getPositionFee(_sizeDelta) + vault.liquidationFeeUsd());
        uint256 priceDelta = ((_collateralDelta - fees) * entryPrice) /
            _sizeDelta;
        liquidationPrice = entryPrice - priceDelta;
    }

    /**
     * @notice Calculate collateral amount in 1e30 usd decimal
     *         given the input amount of token in its own decimals.
     *         considers position fee and swap fees before calculating
     *         output amount.
     * @param _collateralToken  Address of the input token or collateral token.
     * @param _indexToken       Address of the index token to long for.
     * @param _collateralAmount Amount of collateral in collateral token decimals.
     * @param _size             Size of the position usd in 1e30 decimals.
     * @return collateral
     */
    function calculateCollateral(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralAmount,
        uint256 _size
    ) public view returns (uint256 collateral) {
        uint256 marginFees = getPositionFee(_size);
        if (_collateralToken != _indexToken) {
            (collateral, ) = reader.getAmountOut(
                vault,
                _collateralToken,
                _indexToken,
                _collateralAmount
            );
            collateral = vault.tokenToUsdMin(_indexToken, collateral);
        } else {
            collateral = vault.tokenToUsdMin(
                _collateralToken,
                _collateralAmount
            );
        }
        require(marginFees < collateral, "Utils: Fees exceed collateral");
        collateral -= marginFees;
    }

    /**
     * @notice Get size of GMX position amount in usd 1e30 decimals.
     * @param _positionManager Address of the position manager
     *                         delegating the user.
     * @param _indexToken      Address of the index token of
     *                         the long position.
     * @return size
     */
    function getPositionSize(
        address _positionManager,
        address _indexToken
    ) public view returns (uint256 size) {
        (size, , , , , , , ) = vault.getPosition(
            _positionManager,
            _indexToken,
            _indexToken,
            true
        );
    }

    /**
     * @notice Get collateral of GMX position in usd 1e30 decimals.
     * @param _positionManager Address of the position manager
     *                         delegating the user.
     * @param _indexToken      Address of the index token of
     *                         the long position.
     * @return collateral
     */
    function getPositionCollateral(
        address _positionManager,
        address _indexToken
    ) public view returns (uint256 collateral) {
        (, collateral, , , , , , ) = vault.getPosition(
            _positionManager,
            _indexToken,
            _indexToken,
            true
        );
    }

    /**
     * @notice Get funding fee charge-able to a position on GMX.
     * @param _indexToken      Address of the index token of the position.
     * @param _positionManager Address of the position manager
     *                         delegating the user.
     * @param _convertTo       Address of the token to convert to.
     *                         input zero address to get return value
     *                         in usd 1e30 decimal amount.
     * @return fundingFee
     */
    function getFundingFee(
        address _indexToken,
        address _positionManager,
        address _convertTo
    ) public view returns (uint256 fundingFee) {
        (uint256 size, , , uint256 entryFundingRate, , , , ) = vault
            .getPosition(_positionManager, _indexToken, _indexToken, true);

        uint256 fundingRate = (vault.cumulativeFundingRates(_indexToken) +
            vault.getNextFundingRate(_indexToken)) - entryFundingRate;

        fundingFee = (size * fundingRate) / 1000000;

        if (_convertTo != address(0)) {
            fundingFee = vault.usdToTokenMin(_convertTo, fundingFee);
        }
    }

    /**
     * @notice Get a put strike above liquidation to purchase for insuring
     *         a GMX long position.
     * @param _atlanticPool       Address of the atlantic pool options are
     *                            expected to be purchased from.
     * @param _tickSizeMultiplier A multiplier used to increase the impact
     *                            of the ticksize as an offset over liquida-
     *                            tion price.
     * @param _liquidationPrice   Liquidation price of the GMX position.
     */
    function getEligiblePutStrike(
        address _atlanticPool,
        uint256 _tickSizeMultiplier,
        uint256 _liquidationPrice
    ) public view returns (uint256 eligiblePutStrike) {
        IAtlanticPutsPool atlanticPool = IAtlanticPutsPool(_atlanticPool);
        uint256 tickSize = atlanticPool.epochTickSize(
            atlanticPool.currentEpoch()
        );

        uint256 offset = (tickSize * (BPS_PRECISION + _tickSizeMultiplier)) /
            BPS_PRECISION;
        uint256 liquidationWithOffset = _liquidationPrice + offset;

        uint256 noise = liquidationWithOffset % tickSize;
        eligiblePutStrike = liquidationWithOffset - noise;
        if (eligiblePutStrike <= _liquidationPrice + tickSize) {
            eligiblePutStrike = eligiblePutStrike + tickSize;
        }
    }

    /**
     * @notice Get a put strike above liquidation to purchase for insuring
     *         a GMX long position.
     * @param _atlanticPool       Address of the atlantic pool options are
     *                            expected to be purchased from.
     * @param _collateralToken    Address of the input token or collateral
     *                            token used when opening a position.
     * @param _indexToken         Address of the index token of.
     * @param _tickSizeMultiplier A multiplier used to increase the impact
     *                            of the ticksize as an offset over liquida-
     *                            tion price.
     * @param _collateralDelta    Amount of the collateral in collateral to-
     *                            ken decimals.
     * @param _sizeDelta          Size of the position in usd 1e30 decimals.
     * @return eligiblePutStrike
     */
    function getEligiblePutStrike(
        address _atlanticPool,
        address _collateralToken,
        address _indexToken,
        uint256 _tickSizeMultiplier,
        uint256 _collateralDelta,
        uint256 _sizeDelta
    ) external view returns (uint256 eligiblePutStrike) {
        IAtlanticPutsPool atlanticPool = IAtlanticPutsPool(_atlanticPool);
        uint256 tickSize = atlanticPool.epochTickSize(
            atlanticPool.currentEpoch()
        );

        uint256 liquidationPrice = getLiquidationPrice(
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta
        ) / 1e22;

        uint256 offset = (tickSize * (BPS_PRECISION + _tickSizeMultiplier)) /
            BPS_PRECISION;
        liquidationPrice += offset;
        uint256 noise = liquidationPrice % tickSize;
        eligiblePutStrike = liquidationPrice - noise;
        if (eligiblePutStrike < liquidationPrice) {
            eligiblePutStrike = eligiblePutStrike + tickSize;
        }
    }

    /**
     * @notice Get amount of underlying tokens required to unwind an option
     *         purchased from an atlantic pool.
     * @param _atlanticPool Address of the atlantic pool.
     * @param _purchaseId   ID of the options purchase.
     * @param _unwindable   If true, use spot price, if false use strike
     *                      price at which the options will be unwinded
     *                      such that the usd value of underlying tokens
     *                      is equal to the usd value of tokens or collateral
     *                      of the options.
     * @return _cost
     */
    function getAtlanticUnwindCosts(
        address _atlanticPool,
        uint256 _purchaseId,
        bool _unwindable
    ) public view returns (uint256 _cost) {
        (uint256 strike, uint256 optionsAmount) = getOptionsPurchase(
            _atlanticPool,
            _purchaseId
        );
        IAtlanticPutsPool pool = IAtlanticPutsPool(_atlanticPool);
        uint256 unwindAmount = _unwindable
            ? pool.getUnwindAmount(optionsAmount, strike)
            : optionsAmount;
        _cost = unwindAmount;
    }

    /**
     * @notice Get amount of _outToken tokens received when a position
     *         is closed.
     * @param _positionManager Address of the position manager
     *                         delegating the user.
     * @param _indexToken      Address of the GMX position's index token.
     * @param _outToken        Address of the token to convert the receiva-
     *                         able amount to.
     * @return amountOut
     */
    function getAmountReceivedOnExitPosition(
        address _positionManager,
        address _indexToken,
        address _outToken
    ) external view returns (uint256 amountOut) {
        (uint256 size, uint256 collateral, , , , , , ) = vault.getPosition(
            _positionManager,
            _indexToken,
            _indexToken,
            true
        );

        uint256 usdOut = collateral -
            (getFundingFee(_indexToken, _positionManager, address(0)) +
                getPositionFee(size));

        (bool hasProfit, uint256 delta) = vault.getPositionDelta(
            _positionManager,
            _indexToken,
            _indexToken,
            true
        );

        uint256 adjustDelta = (size * delta) / size;

        if (hasProfit) {
            usdOut += adjustDelta;
        } else {
            if (adjustDelta > usdOut) {
                return 0;
            }
            usdOut -= adjustDelta;
        }

        amountOut = vault.usdToTokenMin(_indexToken, usdOut);
        if (_outToken != address(0)) {
            (amountOut, ) = reader.getAmountOut(
                vault,
                _indexToken,
                _outToken,
                amountOut
            );
        }
    }

    /**
     * @notice Check if collateral amount is sufficient
     *         to open a long position.
     * @param _collateralSize  Amount of collateral in its own decimals
     * @param _size            Total Size of the position in usd 1e30
     *                         decimals.
     * @param _collateralToken Address of the collateral token or input
     *                         token.
     * @param _indexToken      Address of the index token longing on.
     */
    function validateIncreaseExecution(
        uint256 _collateralSize,
        uint256 _size,
        address _collateralToken,
        address _indexToken
    ) public view returns (bool) {
        if (_collateralToken != _indexToken) {
            (_collateralSize, ) = reader.getAmountOut(
                vault,
                _collateralToken,
                _indexToken,
                _collateralSize
            );
        }
        return
            vault.tokenToUsdMin(_indexToken, _collateralSize) <
            getPositionFee(_size) + vault.liquidationFeeUsd();
    }

    /**
     * @notice Check if a position has enough collateral to
     *         unwind options.
     * @param _positionManager Address of the position manager
     *                         delegating the user.
     * @param _indexToken      Address of the index token of
     *                         the long position.
     * @param _atlanticPool    Address of the atlantic pool.
     * @param _purchaseId      ID of the options purchase.
     */
    function validateUnwind(
        address _positionManager,
        address _indexToken,
        address _atlanticPool,
        uint256 _purchaseId
    ) public view returns (bool) {
        return
            getUsdOutForUnwindWithFee(
                _positionManager,
                _indexToken,
                _atlanticPool,
                _purchaseId
            ) < getPositionCollateral(_positionManager, _indexToken);
    }

    /**
     * @notice Get usd 30 decimal amount required to remove
     *         from a gmx position to receive required
     *         unwind amount for options.
     * @param _positionManager Address of the position manager
     *                         delegating the user.
     * @param _indexToken      Address of the index token of
     *                         the long position.
     * @param _atlanticPool    Address of the atlantic pool.
     * @param _purchaseId      ID of the options purchase.
     * @return _usdOut
     */
    function getUsdOutForUnwindWithFee(
        address _positionManager,
        address _indexToken,
        address _atlanticPool,
        uint256 _purchaseId
    ) public view returns (uint256 _usdOut) {
        _usdOut =
            vault.tokenToUsdMin(
                _indexToken,
                getAtlanticUnwindCosts(_atlanticPool, _purchaseId, true)
            ) +
            vault.usdToTokenMin(
                _indexToken,
                getFundingFee(_indexToken, _positionManager, address(0)) +
                    getPositionFee(
                        getPositionSize(_positionManager, _indexToken)
                    )
            );
    }

    /**
     * @notice Get the swap path on exiting strategy based on spot
     *         price and put strike of the option purchased.
     * @param _atlanticPool Address of the atlantic pool.
     * @param _purchaseId   ID of the options purchase.
     * @return path
     */
    function getStrategyExitSwapPath(
        address _atlanticPool,
        address _indexToken,
        address _positionManager,
        uint256 _purchaseId
    ) external view returns (address[] memory path) {
        (uint256 strike, ) = getOptionsPurchase(_atlanticPool, _purchaseId);
        IAtlanticPutsPool pool = IAtlanticPutsPool(_atlanticPool);
        address indexToken = pool.addresses().baseToken;

        uint256 fees = (getFundingFee(
            _indexToken,
            _positionManager,
            address(0)
        ) + getPositionFee(getPositionSize(_positionManager, _indexToken))) /
            10 ** (USDG_DECIMALS - STRIKE_DECIMALS);

        strike =
            ((strike + fees) *
                (BPS_PRECISION +
                    IDopexPositionManager(_positionManager).minSlippageBps())) /
            BPS_PRECISION;

        if (strike >= getPrice(pool.addresses().baseToken)) {
            path = get1TokenSwapPath(indexToken);
        } else {
            path = get2TokenSwapPath(indexToken, pool.addresses().quoteToken);
        }
    }

    /**
     * @notice Gets amount of options of a strike required
     *         to insure a collateral amount in 1e30 decimals
     * @param _putStrike          Strike of atlantic put option.
     * @param _sizeCollateralDiff difference of size and collateral
     *                            of the GMX position.
     * @param _quoteToken          Quote token of the atlantic pool
     *                            or address of the collateral token.
     */
    function getRequiredAmountOfOptionsForInsurance(
        uint256 _putStrike,
        uint256 _sizeCollateralDiff,
        address _quoteToken
    ) public view returns (uint256 optionsAmount) {
        require(_sizeCollateralDiff > 0, "Utils: GMX Invalid Position");
        uint256 multiplierForDecimals = 10 **
            (OPTIONS_TOKEN_DECIMALS - IERC20(_quoteToken).decimals());
        optionsAmount =
            ((vault.usdToTokenMin(_quoteToken, _sizeCollateralDiff) *
                10 ** (STRIKE_DECIMALS)) / _putStrike) *
            multiplierForDecimals;
    }

    /**
     * @notice Get required amount of options for insuring
     *         a long position on gmx based on size and collateral
     *         delta.
     * @param _putStrike Strike of atlantic put option.
     * @param _positionManager Address of the position manager
     *                         delegating the user.
     * @param _indexToken      Address of the index token of
     *                         the long position.
     * @param _quoteToken      Quote token of the atlantic pool
     *                         or address of the collateral token.
     * @return optionsAmount
     */
    function getRequiredAmountOfOptionsForInsurance(
        uint256 _putStrike,
        address _positionManager,
        address _indexToken,
        address _quoteToken
    ) external view returns (uint256 optionsAmount) {
        (uint256 size, uint256 collateral, , , , , , ) = vault.getPosition(
            _positionManager,
            _indexToken,
            _indexToken,
            true
        );
        optionsAmount = getRequiredAmountOfOptionsForInsurance(
            _putStrike,
            size - collateral,
            _quoteToken
        );
    }

    /**
     * @notice Get amount of collateral that can be accessed or unlocked
     *         from atlantic options.
     * @param _atlanticPool      Address of the atlantic pool.
     * @param _purchaseId        ID of the options purchase.
     * @return _collateralAccess Amount of collateral in quote token
     *                           decimals of the atlantic pool.
     */
    function getCollateralAccess(
        address _atlanticPool,
        uint256 _purchaseId
    ) public view returns (uint256 _collateralAccess) {
        (uint256 strike, uint256 amount) = getOptionsPurchase(
            _atlanticPool,
            _purchaseId
        );
        _collateralAccess = IAtlanticPutsPool(_atlanticPool).strikeMulAmount(
            strike,
            amount
        );
    }

    function getMarginFees(
        address _positionManager,
        address _indexToken,
        address _convertTo
    ) external view returns (uint256 fees) {
        fees = vault.usdToTokenMin(
            _convertTo,
            getFundingFee(_indexToken, _positionManager, address(0)) +
                getPositionFee(getPositionSize(_positionManager, _indexToken))
        );
    }

    /**
     * @notice Get amount required to swap from one get an expected amount
     *         of another token on GMX vault.
     * @param _amountOut Expected amount out.
     * @param _slippage  Bps of slippage in 1e5 decimals to consider.
     * @param _tokenOut  Address of the token to swap to.
     * @param _tokenIn   Address of the token to swap from.
     */

    function getAmountIn(
        uint256 _amountOut,
        uint256 _slippage,
        address _tokenOut,
        address _tokenIn
    ) public view returns (uint256 _amountIn) {
        uint256 amountIn = (_amountOut * vault.getMaxPrice(_tokenOut)) /
            vault.getMinPrice(_tokenIn);
        uint256 usdgAmount = (amountIn * vault.getMaxPrice(_tokenOut)) / 1e30;
        usdgAmount = vault.adjustForDecimals(
            usdgAmount,
            _tokenIn,
            vault.usdg()
        );
        uint256 feeBps = _getSwapFeeBasisPoints(
            usdgAmount,
            _tokenIn,
            _tokenOut
        ) + (_slippage / 10);

        uint256 amountInWithFees = (amountIn * SWAP_BPS_PRECISION) /
            (SWAP_BPS_PRECISION - feeBps);
        _amountIn = vault.adjustForDecimals(
            amountInWithFees,
            _tokenOut,
            _tokenIn
        );
    }

    /**
     * @notice Calculate the swap fee basis points to be used to calculate
     *         swap fees on GMX vault.
     * @param _usdgAmount USDG amount of the token in 1e18 decimals.
     * @param _tokenIn    Input token or token to be swapped.
     * @param _tokenOut   Output token or token to be swapped to.
     * @return feeBasisPoints
     */
    function _getSwapFeeBasisPoints(
        uint256 _usdgAmount,
        address _tokenIn,
        address _tokenOut
    ) private view returns (uint256 feeBasisPoints) {
        uint256 baseBps = vault.swapFeeBasisPoints(); // swapFeeBasisPoints
        uint256 taxBps = vault.taxBasisPoints(); // taxBasisPoints
        uint256 feesBasisPoints0 = vault.getFeeBasisPoints(
            _tokenIn,
            _usdgAmount,
            baseBps,
            taxBps,
            true
        );
        uint256 feesBasisPoints1 = vault.getFeeBasisPoints(
            _tokenOut,
            _usdgAmount,
            baseBps,
            taxBps,
            false
        );
        // use the higher of the two fee basis points
        feeBasisPoints = feesBasisPoints0 > feesBasisPoints1
            ? feesBasisPoints0
            : feesBasisPoints1;
    }

    /**
     * @notice Fetch reciept like data type of an active option purchased
     *         from an atlantic pool.
     * @param _atlanticPool Address of the atlantic pool the option was
     *                      purchased from.
     * @param _purchaseId   ID of the option purchase.
     */
    function getOptionsPurchase(
        address _atlanticPool,
        uint256 _purchaseId
    ) public view returns (uint256, uint256) {
        OptionsPurchase memory options = IAtlanticPutsPool(_atlanticPool)
            .getOptionsPurchase(_purchaseId);
        return (options.optionStrike, options.optionsAmount);
    }

    /**
     * @notice Fetch the unique key created when a position manager
     *         calls GMX position router contract to create an order
     *         the return key is directly linked to the order in the GMX
     *         position router contract.
     * @param  _positionManager Address of the position manager
     * @param  _isIncrease      Whether to create an order to increase
     *                          collateral size of a position or decrease
     *                          it.
     * @return key
     */
    function getPositionKey(
        address _positionManager,
        bool _isIncrease
    ) public view returns (bytes32 key) {
        if (_isIncrease) {
            key = positionRouter.getRequestKey(
                _positionManager,
                positionRouter.increasePositionsIndex(_positionManager)
            );
        } else {
            key = positionRouter.getRequestKey(
                _positionManager,
                positionRouter.decreasePositionsIndex(_positionManager)
            );
        }
    }

    /**
     * @notice Create and return an array of 1 item.
     * @param _token Address of the token.
     * @return path
     */
    function get1TokenSwapPath(
        address _token
    ) public pure returns (address[] memory path) {
        path = new address[](1);
        path[0] = _token;
    }

    /**
     * @notice Create and return an 2 item array of addresses used for
     *         swapping.
     * @param _token1 Token in or input token.
     * @param _token2 Token out or output token.
     * @return path
     */
    function get2TokenSwapPath(
        address _token1,
        address _token2
    ) public pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = _token1;
        path[1] = _token2;
    }

    /**
     * @notice Fetch price of a token from GMX's pricefeed contract.
     * @param _token  Address of the token to fetch price for.
     * @return _price Price of the token in 1e8 decimals.
     */
    function getPrice(address _token) public view returns (uint256 _price) {
        return
            IVaultPriceFeed(vault.priceFeed()).getPrice(
                _token,
                false,
                false,
                false
            ) / 10 ** (USDG_DECIMALS - STRIKE_DECIMALS);
    }

    /**
     * @notice Get fee charged on opening and closing a position on gmx.
     * @param  _size  Total size of the position in 30 decimal usd precision value.
     * @return feeUsd Fee in 30 decimal usd precision value.
     */
    function getPositionFee(
        uint256 _size
    ) public view returns (uint256 feeUsd) {
        address gov = vault.gov();
        uint256 marginFeeBps = IVault(gov).marginFeeBasisPoints();
        feeUsd = _size - ((_size * (10000 - marginFeeBps)) / 10000);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Utils: Forbidden");
        _;
    }

    function validateDecreaseCollateralDelta(
        address _positionManager,
        address _indexToken,
        uint256 _collateralDelta
    ) external view returns (bool valid) {
        (uint256 size, uint256 collateral, , , , , , ) = vault.getPosition(
            _positionManager,
            _indexToken,
            _indexToken,
            true
        );

        (bool hasProfit, uint256 delta) = vault.getPositionDelta(
            _positionManager,
            _indexToken,
            _indexToken,
            true
        );

        uint256 feeUsd = getFundingFee(
            _indexToken,
            _positionManager,
            address(0)
        ) + getPositionFee(size);

        collateral -= _collateralDelta;
        delta += feeUsd;

        uint256 newLeverage = (size * 10000) / collateral;

        valid = true;

        if (vault.maxLeverage() > newLeverage) {
            valid = false;
        }

        if (!hasProfit && delta > collateral) {
            valid = false;
        }
    }
}

