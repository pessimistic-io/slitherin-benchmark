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

pragma solidity 0.8.6;

import "./ERC721.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IPoolDDL.sol";
import "./console.sol";

abstract contract DDL is Ownable {
    using SafeERC20 for IERC20;

    uint256 public LTV;
    uint256 public LTV_DECIMALS = 10**4;

    IERC721 public collateralToken;
    IERC20 public USDC;

    uint256 public interestRate = 19025875190258754083880960;
    uint256 public INTEREST_RATE_DECIMALS = 10**30;

    uint256 public minBorrowLimit;
    uint256 public COLLATERAL_DECIMALS;

    IPoolDDL public pool;

    struct BorrowedByCollateral {
        uint256 borrowed;
        uint256 newBorrowTimestamp;
    }

    mapping(uint256 => BorrowedByCollateral) public borrowedByCollateral;
    mapping(uint256 => address) public collateralOwner;

    event Borrow(
        address indexed user,
        uint256 indexed id,
        uint256 amount,
        address strategy,
        uint256 timestamp
    );

    event Repay(address indexed user, uint256 indexed optionID, uint256 amount);
    event Liquidate(
        address indexed user,
        uint256 indexed optionID,
        uint256 amount,
        uint256 poolProfit,
        uint256 liqFee
    );
    event Unlock(address indexed user, uint256 indexed optionID);
    event ForcedExercise(
        address indexed user,
        uint256 indexed optionID,
        uint256 amount,
        uint256 poolProfit,
        uint256 liqFee
    );
    event LiquidateByBorderPrice(
        address indexed user,
        uint256 indexed optionID,
        uint256 userReturn,
        uint256 poolReturn,
        uint256 liqFee
    );

    constructor(
        IERC721 _collateralToken,
        IERC20 _USDC,
        uint256 _minBorrowLimit,
        uint256 _ltv,
        uint256 _COLLATERAL_DECIMALS
    ) {
        collateralToken = _collateralToken;
        USDC = _USDC;
        minBorrowLimit = _minBorrowLimit;
        LTV = _ltv;
        COLLATERAL_DECIMALS = 10**_COLLATERAL_DECIMALS;
    }

    /**
     * @notice used to set LTV coefficient
     * @param value LTV coefficient.
     **/
    function setLTV(uint256 value) external onlyOwner {
        require(value <= 8000, "invalid value");
        LTV = value;
    }

    /**
     * @notice used to set new interest rate
     * @param value interest rate (in minutes)
     **/
    function setInterestRate(uint256 value) external onlyOwner {
        interestRate = value;
    }

    function setInterestRateDecimals(uint256 value) external onlyOwner {
        INTEREST_RATE_DECIMALS = value;
    }

    /**
     * @notice used to set the minimum borrow size
     * @param value min. borrow size (USDC)
     **/
    function setMinBorrowLimit(uint256 value) external onlyOwner {
        minBorrowLimit = value;
    }

    /**
     * @notice used to connect a new liqidity pool
     * @param value the address of the liquidity pool
     **/
    function setPool(address value) external onlyOwner {
        pool = IPoolDDL(value);
    }

    /**
     * @notice used to lock the collateral (ERC-721) in DeDeLend
     * @param id collateral ID
     **/
    function lockCollateral(uint256 id) external {
        require(pool.openDeDeLend(), "pauseDeDeLend");
        require(collateralToken.ownerOf(id) == msg.sender, "you not owner");
        collateralOwner[id] = msg.sender;
        _lockCollateral(id, msg.sender);
    }

    function _lockCollateral(uint256 id, address user) internal virtual;

    /**
     * @notice calcualtes the maximum borrow size
     * for the specific collateral
     * @param id collateral ID
     **/
    function maxBorrowLimit(uint256 id) public view returns (uint256) {
        return (intrinsicValueOf(id) / LTV_DECIMALS) * LTV;
    }

    /**
     * @notice send USDC to the user
     * @param id collateral ID
     * @param amount borrow size (USDC)
     **/
    function borrow(uint256 id, uint256 amount) external {
        require(pool.openDeDeLend(), "pauseDeDeLend");
        BorrowedByCollateral storage data = borrowedByCollateral[id];
        uint256 maxLimit = maxBorrowLimit(id);
        uint256 totalBalance = pool.getTotalBalance();
        require(amount >= minBorrowLimit, "amount less minBorrowLimit");
        require(amount + data.borrowed <= maxLimit, "borrow is too big");
        require(msg.sender == collateralOwner[id], "you are not the owner");
        require(
            amount <= totalBalance,
            "there is not enough money in the pool"
        );
        _isAvaialbleToBorrow(id);
        if (isLong(id)) {
            require(currentPrice(id) > borderPrice(id), "the price is too low");
        } else {
            require(
                currentPrice(id) < borderPrice(id),
                "the price is too high"
            );
        }
        uint256 upcomingFee = calculateUpcomingFee(id);
        borrowedByCollateral[id] = BorrowedByCollateral(
            amount + data.borrowed + upcomingFee,
            block.timestamp
        );
        pool.addTotalLocked(amount + upcomingFee);
        pool.send(collateralOwner[id], amount);
        _emitBorrow(msg.sender, id, amount, block.timestamp);
    }

    function _isAvaialbleToBorrow(uint256 id) internal virtual;

    function _emitBorrow(
        address user,
        uint256 id,
        uint256 amount,
        uint256 timestamp
    ) internal virtual;

    /**
     * @notice used to calculate how much USDC
     * user should pay as interest fee
     * @param id collateral ID
     **/
    function calculateUpcomingFee(uint256 id)
        public
        view
        returns (uint256 upcomingFee)
    {
        BorrowedByCollateral storage data = borrowedByCollateral[id];
        uint256 periodInMinutes = (block.timestamp - data.newBorrowTimestamp) /
            60;
        upcomingFee =
            ((data.borrowed / 100) * (periodInMinutes * interestRate)) /
            INTEREST_RATE_DECIMALS;
    }

    /**
     * @notice used to repay the user's debt
     * @param id collateral ID
     * @param amount amount to repay (USDC)
     **/
    function repay(uint256 id, uint256 amount) external {
        require(borrowedByCollateral[id].borrowed > 0, "option redeemed");
        uint256 upcomingFee = calculateUpcomingFee(id);
        require(
            amount <= borrowedByCollateral[id].borrowed + upcomingFee,
            "amount is too big"
        );
        require(msg.sender == collateralOwner[id]);
        uint256 newBorrow = borrowedByCollateral[id].borrowed +
            upcomingFee -
            amount;
        pool.subTotalLocked(amount - upcomingFee);
        borrowedByCollateral[id] = BorrowedByCollateral(
            newBorrow,
            block.timestamp
        );
        USDC.transferFrom(collateralOwner[id], address(this), amount);
        USDC.transfer(address(pool), amount);
        emit Repay(msg.sender, id, amount);
    }

    /**
     * @notice sends the collateral token back to the user
     * @param id collateral ID
     **/
    function unlock(uint256 id) public {
        require(borrowedByCollateral[id].borrowed == 0, "loan is locked");
        collateralToken.transferFrom(address(this), collateralOwner[id], id);
        emit Unlock(msg.sender, id);
    }

    function isLong(uint256 id) public view virtual returns (bool);

    function collateralState(uint256 id) public view returns (bool) {
        if (isLong(id)) {
            return currentPrice(id) <= liqPrice(id);
        } else {
            return currentPrice(id) >= liqPrice(id);
        }
    }

    function collateralStateByBorderPrice(uint256 id)
        public
        view
        returns (bool)
    {
        if (isLong(id)) {
            return currentPrice(id) <= borderPrice(id);
        } else {
            return currentPrice(id) >= borderPrice(id);
        }
    }

    function currentPrice(uint256 id)
        public
        view
        virtual
        returns (uint256 price)
    {}

    /**
     * @param id positon ID
     * @notice returns the position size and the entryPrice
     **/
    function collateralInfo(uint256 id)
        public
        view
        virtual
        returns (uint256 amount, uint256 price);

    function borderPriceCoefByIndexToken(uint256 id)        
        public
        view
        virtual 
        returns (uint256 borderPriceCoef);

    function borderPrice(uint256 id) public view returns (uint256 price) {
        (, uint256 openPrice) = collateralInfo(id);
        uint256 priceCoef = borderPriceCoefByIndexToken(id);
        if (isLong(id)) {
            return (openPrice * (100 + priceCoef)) / 100;
        }
        return (openPrice * (100 - priceCoef)) / 100;
    }

    function liqPrice(uint256 id) public view returns (uint256 price) {
        BorrowedByCollateral storage data = borrowedByCollateral[id];
        (uint256 amount, uint256 openPrice) = collateralInfo(id);
        if (isLong(id)) {
            return
                openPrice + ((data.borrowed * 1e6) / (amount * 1e8/openPrice)) * 120 / 100 * 100;
        }
        return
            openPrice - ((data.borrowed * 1e6) / (amount * 1e8/openPrice)) * 120 / 100 * 100;
    }

    function currentTriggerPrice(uint256 id)
        public
        view
        returns (uint256 price)
    {
        if (isLong(id)) {
            if (borderPrice(id) > liqPrice(id)) {
                return borderPrice(id);
            }
            return liqPrice(id);
        }
        if (borderPrice(id) < liqPrice(id)) {
            return borderPrice(id);
        }
        return liqPrice(id);
    }

    /**
     * @notice position's value
     * @param id position ID
     **/
    function intrinsicValueOf(uint256 id)
        public
        view
        virtual
        returns (uint256 profit);
}

