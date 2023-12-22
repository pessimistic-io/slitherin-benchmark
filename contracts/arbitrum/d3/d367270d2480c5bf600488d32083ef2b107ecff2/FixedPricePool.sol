// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./Base.sol";

contract FixedPricePool is Base {
    using SafeMath for uint;

    event ReserveTokens(address indexed user, uint reserveAmount, uint pricePaid);

    uint public price; // price in wei for PRICE_DENOMINATOR token units

    constructor(IERC20 _token, 
                uint _tokenAmountToSell, 
                uint _startTime, 
                uint _endTime, 
                uint _minimumFillPercentage, 
                uint _minimumOrderSize, 
                uint[] memory _maximumAllocation,
                uint[] memory _minimumStakeTiers,
                uint _claimLockDuration,
                uint _price, 
                address payable _assetManager, 
                address _projectAdmin, 
                address _platformAdmin,
                IStaking _stakingContract,
                IWhitelist _whitelistContract) 
        Base(_token, 
                  _tokenAmountToSell, 
                  _startTime, 
                  _endTime, 
                  _minimumFillPercentage, 
                  _minimumOrderSize, 
                  _maximumAllocation,
                  _minimumStakeTiers,
                  _claimLockDuration,
                  _assetManager, 
                  _projectAdmin, 
                  _platformAdmin,
                  _stakingContract,
                  _whitelistContract)
    {
        price = _price;
    }

    function changePrice(uint newPrice) public onlyProjectAdmin onlyDuringInitialized {
        price = newPrice;
    }

    function setPoolReady() public override onlyProjectAdmin onlyDuringInitialized {
        maximumFunding = tokenAmountToSell.mul(price).div(PRICE_DENOMINATOR);
        super.setPoolReady();
    }

    function _reserveTokens(address user, uint reserveAmount, uint pricePaid) internal {
        userToReserve[user] += reserveAmount;
        amountPaid[user] += pricePaid;

        tokenAmountSold += reserveAmount;
        tokenAmountLeft -= reserveAmount;

        fundRaised += pricePaid;

        if (tokenAmountLeft == 0) {
            _setPoolSuccess();
        }
        
        emit ReserveTokens(user, reserveAmount, pricePaid);
    }

    function reserve() public virtual payable onlyDuringOngoing {
        require(msg.value >= minimumOrderSize, "FP: ORDER_TOO_SMALL");
        uint maxAllocation;
        if (address(whitelistContract) != address(0)){
            uint tier = _getUserTier();
            maxAllocation = _getStakeTierMaxAllocation(tier);
        } else {
            maxAllocation = maximumAllocation[0];
        }
        

        require(amountPaid[msg.sender] < maxAllocation, "FP: MAX_ALLOCATION_REACHED");

        uint payValue = Math.min(msg.value, maxAllocation - amountPaid[msg.sender]);

        uint reserveAmount = Math.min(payValue.mul(PRICE_DENOMINATOR).div(price), tokenAmountLeft);

        uint totalPrice = reserveAmount.mul(price).div(PRICE_DENOMINATOR);

        require(totalPrice > 0 && reserveAmount > 0, "FP: MAX_ALLOCATION_REACHED");

        _reserveTokens(msg.sender, reserveAmount, totalPrice);

        if (msg.value.sub(totalPrice) >= SENDBACK_THRESHOLD) msg.sender.transfer(msg.value.sub(totalPrice));
    }
}
