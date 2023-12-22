// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IPriceOracle.sol";
import "./SafeMath.sol";

/**
 * @title PriceConvertor
 * @notice PriceConvertor contract to convert token prices
 */
library PriceConvertor {
    using SafeMath for uint256;
    
    uint constant public PRICE_PRECISION = 1e8;
    
    /**
     * Transfer tokens from one address to another
     * @param amount Amount of token 1 to transfer
     * @param t1Price Price of token 1
     * @param t2Price Price of token 2
     */
    function t1t2(uint amount, uint t1Price, uint t2Price) internal pure returns(uint) {
        return amount.mul(t1Price).div(t2Price);
    }

    /**
     * Token amount to USD amount
     * @param amount Amount of token to convert
     * @param price Price of token
     */
    function toUSD(uint amount, uint price) internal pure returns(uint){
        return amount.mul(price).div(PRICE_PRECISION);
    }

    /**
     * USD amount to token amount
     * @param amount Amount of USD to convert
     * @param price Price of token
     */
    function toToken(uint amount, uint price) internal pure returns(uint){
        return amount.mul(PRICE_PRECISION).div(price);
    }
}
