//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import {IPositionRouter} from "./IPositionRouter.sol";
import {IVaultPriceFeed} from "./IVaultPriceFeed.sol";
import {IReader} from "./IReader.sol";
import {IVault} from "./IVault.sol";
import {IAtlanticPutsPool} from "./IAtlanticPutsPool.sol";
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

    function getPositionLeverage(address _positionManager, address _indexToken)
        public
        view
        returns (uint256)
    {
        return
            vault.getPositionLeverage(
                _positionManager,
                _indexToken,
                _indexToken,
                true
            );
    }

    function getLiquidationPrice(address _positionManager, address _indexToken)
        public
        view
        returns (uint256 liquidationPrice)
    {
        uint256 leverage = getPositionLeverage(_positionManager, _indexToken);

        (uint256 size, , uint256 entryPrice, , , , , ) = vault.getPosition(
            _positionManager,
            _indexToken,
            _indexToken,
            true
        );

        liquidationPrice =
            entryPrice -
            (
                ((entryPrice * 10**USDG_DECIMALS) /
                    (leverage * 10**(USDG_DECIMALS - 4)))
            ) +
            getFundingFee(_indexToken, _positionManager, address(0)) +
            getPositionFee(size);
    }

    function getLiquidationPrice(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta
    ) public view returns (uint256 liquidationPrice) {
        uint256 markPrice = getPrice(_indexToken) * 1e22;

        uint256 leverage = (_sizeDelta * 1e30) /
            calculateCollateral(
                _collateralToken,
                _indexToken,
                _collateralDelta,
                _sizeDelta
            );
        liquidationPrice =
            (markPrice - ((markPrice * 1e30) / leverage)) +
            getPositionFee(_sizeDelta);
        liquidationPrice =
            liquidationPrice /
            10**(USDG_DECIMALS - STRIKE_DECIMALS);
    }

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

    function getPositionSize(address _positionManager, address _indexToken)
        public
        view
        returns (uint256 size)
    {
        (size, , , , , , , ) = vault.getPosition(
            _positionManager,
            _indexToken,
            _indexToken,
            true
        );
    }

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

    function getFundingFee(
        address _indexToken,
        address _positionManager,
        address _convertTo
    ) public view returns (uint256 fundingFee) {
        (uint256 size, , , uint256 entryFundingRate, , , , ) = vault
            .getPosition(_positionManager, _indexToken, _indexToken, true);
        uint256 currentCummulativeFundingRate = vault.cumulativeFundingRates(
            _indexToken
        ) + vault.getNextFundingRate(_indexToken);
        if (currentCummulativeFundingRate != 0) {
            fundingFee =
                (size * (currentCummulativeFundingRate - entryFundingRate)) /
                1000000;
        }
        if (fundingFee != 0) {
            if (_convertTo != address(0)) {
                fundingFee = vault.usdToTokenMin(_convertTo, fundingFee);
            }
        }
    }

    function getEligblePutStrike(
        address _atlanticPool,
        uint256 _liquidationPrice
    ) public view returns (uint256 eligiblePutStrike) {
        IAtlanticPutsPool atlanticPool = IAtlanticPutsPool(_atlanticPool);
        uint256 tickSize = atlanticPool.epochTickSize(
            atlanticPool.currentEpoch()
        );
        uint256 noise = _liquidationPrice % tickSize;
        eligiblePutStrike = _liquidationPrice - noise;
        if (_liquidationPrice > eligiblePutStrike) {
            eligiblePutStrike = eligiblePutStrike + tickSize;
        }
    }

    function getAtlanticPutOptionCosts(
        address _atlanticPool,
        uint256 _strike,
        uint256 _amount
    ) public view returns (uint256 _cost) {
        IAtlanticPutsPool pool = IAtlanticPutsPool(_atlanticPool);
        _cost =
            pool.calculatePremium(_strike, _amount) +
            pool.calculatePurchaseFees(_strike, _amount);
    }

    function getAtlanticUnwindCosts(
        address _atlanticPool,
        uint256 _purchaseId,
        bool _unwindable
    ) public view returns (uint256 _cost) {
        (uint256 strike, uint256 optionsAmount, ) = getOptionsPurchase(
            _atlanticPool,
            _purchaseId
        );
        IAtlanticPutsPool pool = IAtlanticPutsPool(_atlanticPool);
        uint256 unwindAmount = _unwindable
            ? pool.getUnwindAmount(optionsAmount, strike)
            : optionsAmount;
        _cost = unwindAmount + pool.calculateUnwindFees(optionsAmount);
    }

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
            _collateralSize <
            vault.usdToTokenMin(_indexToken, getPositionFee(_size));
    }

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

    function getStrategyExitSwapPath(address _atlanticPool, uint256 _purchaseId)
        external
        view
        returns (address[] memory path)
    {
        (uint256 strike, , ) = getOptionsPurchase(_atlanticPool, _purchaseId);
        IAtlanticPutsPool pool = IAtlanticPutsPool(_atlanticPool);
        address indexToken = pool.addresses().baseToken;

        if (getPrice(pool.addresses().baseToken) < strike) {
            path = get1TokenSwapPath(indexToken);
        } else {
            path = get2TokenSwapPath(indexToken, pool.addresses().quoteToken);
        }
    }

    function calculateInsuranceOptionsAmount(
        address _collateralToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _putStrike
    ) public view returns (uint256 optionsAmount) {
        optionsAmount =
            (vault.usdToTokenMin(
                _collateralToken,
                _sizeDelta - _collateralDelta
            ) *
                10 **
                    ((STRIKE_DECIMALS + OPTIONS_TOKEN_DECIMALS) -
                        IERC20(_collateralToken).decimals())) /
            _putStrike;
    }

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
                10**(STRIKE_DECIMALS)) / _putStrike) *
            multiplierForDecimals;
    }

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

    function getCollateralAccess(address atlanticPool, uint256 _purchaseId)
        public
        view
        returns (uint256 _collateralAccess)
    {
        (uint256 strike, uint256 amount, ) = getOptionsPurchase(
            atlanticPool,
            _purchaseId
        );
        _collateralAccess = IAtlanticPutsPool(atlanticPool).strikeMulAmount(
            strike,
            amount
        );
    }

    function calculateLeverage(
        uint256 _size,
        uint256 _collateral,
        address _collateralToken
    ) external view returns (uint256 _leverage) {
        return
            ((_size * 10**(USDG_DECIMALS)) /
                vault.tokenToUsdMin(_collateralToken, _collateral)) /
            10**(USDG_DECIMALS - 4);
    }

    function getRelockAmount(address atlanticPool, uint256 _purchaseId)
        public
        view
        returns (uint256 relockAmount)
    {
        IAtlanticPutsPool pool = IAtlanticPutsPool(atlanticPool);
        (
            uint256 strike,
            uint256 amount,
            uint256 fundingRate
        ) = getOptionsPurchase(atlanticPool, _purchaseId);
        uint256 collateralAccess = pool.strikeMulAmount(strike, amount);
        relockAmount =
            collateralAccess +
            pool.calculateFunding(collateralAccess, fundingRate);
    }

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

    function getOptionsPurchase(address _atlanticPool, uint256 purchaseId)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        OptionsPurchase memory options = IAtlanticPutsPool(_atlanticPool)
            .getOptionsPurchase(purchaseId);
        return (
            options.optionStrike,
            options.optionsAmount,
            options.fundingRate
        );
    }

    function getPositionKey(address _positionManager, bool _isIncrease)
        public
        view
        returns (bytes32 key)
    {
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

    function get1TokenSwapPath(address _token)
        public
        pure
        returns (address[] memory path)
    {
        path = new address[](1);
        path[0] = _token;
    }

    function get2TokenSwapPath(address _token1, address _token2)
        public
        pure
        returns (address[] memory path)
    {
        path = new address[](2);
        path[0] = _token1;
        path[1] = _token2;
    }

    function getPrice(address _token) public view returns (uint256 _price) {
        return
            IVaultPriceFeed(vault.priceFeed()).getPrice(
                _token,
                false,
                false,
                false
            ) / 10**(USDG_DECIMALS - STRIKE_DECIMALS);
    }

    function getPositionFee(uint256 _size)
        public
        view
        returns (uint256 feeUsd)
    {
        address gov = vault.gov();
        uint256 marginFeeBps = IVault(gov).marginFeeBasisPoints();
        feeUsd = _size - ((_size * (10000 - marginFeeBps)) / 10000);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Utils: Forbidden");
        _;
    }
}

