/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DeDeLend
 * Copyright (C) 2022 DeDeLend
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

pragma solidity 0.8.6||0.7.0;

import "./DDL.sol";
import "./IAccountManager.sol";
import "./IVault.sol";
import "./ITimelock.sol";
import "./IPositionRouter.sol";
import "./IOrderBook.sol";
import "./Doppelganger.sol";

contract DDL_GMX is DDL {
    IAccountManager public accountManager;
    IVault public vault;
    IPositionRouter public positionRouter;
    int256 public closeSlippage = 10;
    uint256 internal constant GMX_DECIMALS = 1e30;

    struct PositionInfo {
        address indexToken;
        uint256 amount;
        uint256 openPrice;
        bool isLong;
    }

    struct LiquidatePositionInfo {
        uint256 id;
        address liquidator;
        uint256 amountReturn;
        uint256 profit;
        bool isBorderPrice;
    }

    mapping(uint256 => PositionInfo) public positionInfo;
    mapping(bytes32 => LiquidatePositionInfo) private liquidatePositionInfo;
    mapping(address => uint256) public borderPriceCoef;

    constructor(
        IPositionRouter _positionRouter,
        IAccountManager _accountManager,
        IVault _vault,
        IERC721 _collateralToken,
        IERC20 _USDC,
        uint256 _minBorrowLimit,
        uint256 _ltv,
        uint256 _COLLATERAL_DECIMALS,
        address[4] memory _ArrIndexPrice,
        uint256[4] memory _ArrBorderPriceCoef
    )
        DDL(
            _collateralToken,
            _USDC,
            _minBorrowLimit,
            _ltv,
            _COLLATERAL_DECIMALS
        )
    {
        positionRouter = _positionRouter;
        accountManager = _accountManager;
        vault = _vault;
        for (uint256 i = 0; i < 4; i++) {
            borderPriceCoef[_ArrIndexPrice[i]] = _ArrBorderPriceCoef[i];
        }
    }

    function setBorderPriceCoef(uint256 value, address indexToken) external onlyOwner {
        borderPriceCoef[indexToken] = value;
    }

    /**
     * @notice takes ERC-721 (collateral) from the user and locking in DDL_GMX
     * @param id collateral ID
     * @param user user's address
     **/
    function _lockCollateral(uint256 id, address user) internal override {
        (IAccountManager.Symbols symbol, , bool isLong, , ) = accountManager
            .keyData(id);
        address indexToken = accountManager.indexTokenBySymbol(symbol);
        (uint256 size, , uint256 averagePrice, , , , , ) = accountManager
            .getPosition(id);
        collateralToken.transferFrom(msg.sender, address(this), id);
        positionInfo[id] = PositionInfo(indexToken, size, averagePrice, isLong);
    }

    /**
     * @notice checks the ability to borrow USDC by collateral ID
     * @param id collateral ID
     **/
    function _isAvaialbleToBorrow(uint256 id) internal override {
        (bool isProfit, ) = accountManager.getPositionDelta(id);
        require(isProfit, "no profit");
    }

    function _emitBorrow(
        address user,
        uint256 id,
        uint256 amount,
        uint256 timestamp
    ) internal override {
        emit Borrow(
            user,
            id,
            amount,
            positionInfo[id].indexToken,
            block.timestamp
        );
    }

    /**
     * @notice calculates the intrinsic value of the collateral
     * @param id collateral ID
     **/
    function intrinsicValueOf(uint256 id)
        public
        view
        override
        returns (uint256 delta)
    {
        (bool isProfit, uint256 profit) = accountManager.getPositionDelta(id);
        profit = profit / (GMX_DECIMALS / 1e6);
        return (isProfit ? profit : 0);
    }

    /**
     * @notice closes position on GMX
     * @param id collateral id
     **/
    function _liquidateCollateral(uint256 id, bool isBorderPrice) internal {
        (, address doppelgangerContract, bool isLong, , ) = accountManager
            .keyData(id);
        PositionInfo memory data = positionInfo[id];
        (uint256 closePrice, uint256 size) = liquidateClosePrice(id);
        (address[] memory path, uint256 closeValue) = _preparationData(id);
        Doppelganger(payable(doppelgangerContract)).createDecreasePosition{
            value: msg.value
        }(
            address(this),
            path,
            data.indexToken,
            closeValue,
            size,
            data.isLong,
            closePrice,
            0,
            positionRouter.minExecutionFee(),
            false,
            address(this)
        );
        uint256 amountReturn = decreasePositionReturnValue(
            doppelgangerContract,
            path[0],
            data.indexToken,
            closeValue,
            size,
            isLong
        );
        if (amountReturn > 0) {
            if (path.length > 1) {
                amountReturn = _swap(path[0], path[1], amountReturn);
            }
        }
        informationFromCallback(
            doppelgangerContract,
            id,
            isBorderPrice,
            amountReturn
        );
    }

    function _swap(
        address _tokenIn,
        address _tokenOut,
        uint256 amountIn
    ) internal returns (uint256) {
        uint256 priceIn = vault.getMinPrice(_tokenIn);
        uint256 priceOut = vault.getMaxPrice(_tokenOut);
        uint256 amountOut = (amountIn * priceIn) / priceOut;
        amountOut = vault.adjustForDecimals(amountOut, _tokenIn, _tokenOut);

        uint256 usdgAmount = (amountIn * priceIn) / GMX_DECIMALS;
        usdgAmount = vault.adjustForDecimals(
            usdgAmount,
            _tokenIn,
            vault.usdg()
        );

        uint256 feeBasisPoints = vault.vaultUtils().getSwapFeeBasisPoints(
            _tokenIn,
            _tokenOut,
            usdgAmount
        );
        uint256 amountOutAfterFees = _collectSwapFees(
            _tokenOut,
            amountOut,
            feeBasisPoints
        );
        return amountOutAfterFees;
    }

    function informationFromCallback(
        address doppelgangerContract,
        uint256 id,
        bool isBorderPrice,
        uint256 amountReturn
    ) private {
        uint256 index = positionRouter.decreasePositionsIndex(
            doppelgangerContract
        );
        bytes32 requestKey = positionRouter.getRequestKey(
            doppelgangerContract,
            index
        );
        uint256 profit = intrinsicValueOf(id);
        liquidatePositionInfo[requestKey] = LiquidatePositionInfo(
            id,
            msg.sender,
            amountReturn,
            profit,
            isBorderPrice
        );
    }

    /**
     * @notice used to liquidate the loan
     * @param id position ID
     **/
    function liquidate(uint256 id) external payable {
        require(collateralState(id), "invalid price");
        require(
            msg.value >= positionRouter.minExecutionFee(),
            "minExecutionFee too smal"
        );
        _liquidateCollateral(id, false);
    }

    function borderPriceCoefByIndexToken(uint256 id)         
        public
        view
        override
        returns (uint256 priceCoef) {
            return borderPriceCoef[positionInfo[id].indexToken];
        }

    /**
     * @notice used to liquidate the loan by border price
     * @param id collateral ID
     **/
    function liquidateByBorderPrice(uint256 id) external payable {
        require(collateralStateByBorderPrice(id), "invalid price");
        require(
            msg.value >= positionRouter.minExecutionFee(),
            "minExecutionFee too smal"
        );
        _liquidateCollateral(id, true);
    }

    function gmxPositionCallback(
        bytes32 positionKey,
        bool isExecuted,
        bool isIncrease
    ) external {
        require(
            msg.sender == address(positionRouter),
            "msg.sender is not positionRouter"
        );
        address liquidator = liquidatePositionInfo[positionKey].liquidator;
        if (liquidator != address(0)) {
            uint256 diff = 0;
            uint256 id = liquidatePositionInfo[positionKey].id;
            uint256 borrowed = borrowedByCollateral[id].borrowed;
            uint256 returnValue = liquidatePositionInfo[positionKey]
                .amountReturn;
            uint256 profit = liquidatePositionInfo[positionKey].profit;
            pool.subTotalLocked(borrowed);
            if (liquidatePositionInfo[positionKey].isBorderPrice) {
                USDC.transfer(address(pool), borrowed);
                USDC.transfer(
                    collateralOwner[id],
                    returnValue - (borrowed + (borrowed * 10) / 100)
                );
                USDC.transfer(liquidator, (borrowed * 10) / 100);
                emit LiquidateByBorderPrice(
                    collateralOwner[id],
                    id,
                    returnValue - (borrowed + (borrowed * 10) / 100),
                    borrowed,
                    (borrowed * 10) / 100
                );
            } else {
                if (profit > borrowed) {
                    diff = profit - borrowed;
                    USDC.transfer(address(pool), borrowed + (diff * 90) / 100);
                    USDC.transfer(liquidator, (diff * 10) / 100);
                    USDC.transfer(
                        collateralOwner[id],
                        returnValue -
                            (borrowed + (diff * 90) / 100) -
                            (diff * 10) /
                            100
                    );
                } else {
                    USDC.transfer(address(pool), borrowed);
                    USDC.transfer(collateralOwner[id], returnValue - borrowed);
                }
                emit Liquidate(
                    collateralOwner[id],
                    id,
                    borrowed,
                    (diff * 90) / 100,
                    (diff * 10) / 100
                );
            }
            collateralToken.transferFrom(
                address(this),
                collateralOwner[id],
                id
            );
        }
    }

    function _preparationData(uint256 id)
        internal
        returns (address[] memory path, uint256 closeValue)
    {
        (, uint256 collateral, , , , , , ) = accountManager.getPosition(id);
        (bool isProfit, uint256 delta) = accountManager.getPositionDelta(id);
        closeValue = (isProfit ? collateral : delta);
        if (positionInfo[id].isLong) {
            path = new address[](2);
            path[0] = positionInfo[id].indexToken;
            path[1] = address(USDC);
        } else {
            path = new address[](1);
            path[0] = address(USDC);
        }
    }

    function liquidateClosePrice(uint256 id)
        internal
        returns (uint256 closePrice, uint256 size)
    {
        (size, , , , , , , ) = accountManager.getPosition(id);
        require(size != 0, "position size is null");
        closePrice =
            (accountManager.currentPrice(id) / 1000) *
            uint256(
                positionInfo[id].isLong
                    ? int256(1000) - closeSlippage
                    : int256(1000) + closeSlippage
            );
    }

    function isLong(uint256 id) public view override returns (bool) {
        return accountManager.isLong(id);
    }

    function currentPrice(uint256 id) public view override returns (uint256) {
        PositionInfo memory data = positionInfo[id];
        if (isLong(id)) {
            return vault.getMaxPrice(data.indexToken) / (GMX_DECIMALS / 1e8);
        }
        return vault.getMinPrice(data.indexToken) / (GMX_DECIMALS / 1e8);
    }

    /**
     * @notice returns the position size and the entry price by collateral ID
     * @param id collateral id
     **/
    function collateralInfo(uint256 id)
        public
        view
        override
        returns (uint256 amount, uint256 price)
    {
        (uint256 size, , uint256 averagePrice, , , , , ) = accountManager
            .getPosition(id);
        return (
            size / (GMX_DECIMALS / 1e6),
            averagePrice / (GMX_DECIMALS / 1e8)
        );
    }

    function decreasePositionReturnValue(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong
    ) internal returns (uint256) {
        (uint256 usdOut, uint256 usdOutAfterFee) = _reduceCollateral(
            _account,
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong
        );
        if (usdOut > 0) {
            uint256 amountOutAfterFees = vault.usdToTokenMin(
                _collateralToken,
                usdOutAfterFee
            );
            return amountOutAfterFees;
        }
        return 0;
    }

    function _reduceCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong
    ) private returns (uint256, uint256) {
        (
            uint256 size,
            uint256 collateral,
            uint256 averagePrice,
            uint256 entryFundingRate,
            ,
            ,
            ,
            uint256 lastIncreasedTime
        ) = vault.getPosition(_account, _collateralToken, _indexToken, _isLong);
        uint256 fee = _collectMarginFees(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            _sizeDelta,
            size,
            entryFundingRate
        );
        (bool hasProfit, uint256 delta) = vault.getDelta(
            _indexToken,
            size,
            averagePrice,
            _isLong,
            lastIncreasedTime
        );
        uint256 adjustedDelta = (_sizeDelta * delta) / size;
        uint256 usdOut;
        if (hasProfit && adjustedDelta > 0) {
            usdOut = adjustedDelta;
        }
        if (!hasProfit && adjustedDelta > 0) {
            collateral -= adjustedDelta;
        }
        if (_collateralDelta > 0) {
            usdOut += _collateralDelta;
            collateral -= _collateralDelta;
        }
        if (size == _sizeDelta) {
            usdOut = usdOut + collateral;
        }
        uint256 usdOutAfterFee = usdOut;
        if (usdOut > fee) {
            usdOutAfterFee = usdOut - fee;
        }
        return (usdOut, usdOutAfterFee);
    }

    function _collectMarginFees(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _size,
        uint256 _entryFundingRate
    ) private returns (uint256) {
        uint256 feeUsd = _getPositionFee(_sizeDelta);
        uint256 fundingFee = vault.getFundingFee(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            _size,
            _entryFundingRate
        );
        feeUsd += fundingFee;
        return feeUsd;
    }

    function _collectSwapFees(
        address _token,
        uint256 _amount,
        uint256 _feeBasisPoints
    ) private returns (uint256) {
        uint256 afterFeeAmount = (_amount *
            (vault.BASIS_POINTS_DIVISOR() - _feeBasisPoints)) /
            vault.BASIS_POINTS_DIVISOR();
        return afterFeeAmount;
    }

    function _getPositionFee(uint256 _sizeDelta) private returns (uint256) {
        if (_sizeDelta == 0) {
            return 0;
        }
        uint256 afterFeeUsd = (_sizeDelta *
            (vault.vaultUtils().BASIS_POINTS_DIVISOR() -
                ITimelock(vault.gov()).marginFeeBasisPoints())) /
            vault.vaultUtils().BASIS_POINTS_DIVISOR();
        return _sizeDelta - afterFeeUsd;
    }
}

