// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import "./AggregatorV3Interface.sol";
import "./Denominations.sol";

import "./IPriceConsumer2.sol";

contract PriceConsumer2 is IPriceConsumer2{

    mapping(address => AggregatorV3Interface) private _priceFeeds;
    
    address[20] private _currencies = [
        Denominations.USD, Denominations.GBP, Denominations.EUR, Denominations.JPY, Denominations.KRW, Denominations.CNY,
        Denominations.AUD, Denominations.CAD, Denominations.CHF, Denominations.ARS, Denominations.PHP, Denominations.NZD,
        Denominations.SGD, Denominations.NGN, Denominations.ZAR, Denominations.RUB, Denominations.INR, Denominations.BRL,
        Denominations.ETH, Denominations.BTC
    ];

    /**
     * Network: Arbitrum One
     * ETH/USD (Base_0): 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612
     * GBP/USD (quote_1): 0x9C4424Fd84C6661F97D8d6b3fc3C1aAc2BeDd137
     * EUR/USD (quote_2): 0xA14d53bC1F1c0F31B4aA3BD109344E5009051a84
     * JPY/USD (quote_3): 0x3dD6e51CB9caE717d5a8778CF79A04029f9cFDF8
     * KRW/USD (quote_4): 0x85bb02E0Ae286600d1c68Bb6Ce22Cc998d411916
     * CNY/USD (quote_5): 0xcC3370Bde6AFE51e1205a5038947b9836371eCCb
     * AUD/USD (quote_6): 0x9854e9a850e7C354c1de177eA953a6b1fba8Fc22
     * CAD/USD (quote_7): 0xf6DA27749484843c4F02f5Ad1378ceE723dD61d4
     * CHF/USD (quote_8): 0xe32AccC8c4eC03F6E75bd3621BfC9Fbb234E1FC3
     * ARS/USD (quote_9): 0x0000000000000000000000000000000000000000
     * PHP/USD (quote_10): 0xfF82AAF635645fD0bcc7b619C3F28004cDb58574
     * NZD/USD (quote_11): 0x0000000000000000000000000000000000000000
     * SGD/USD (quote_12): 0xF0d38324d1F86a176aC727A4b0c43c9F9d9c5EB1
     * NGN/USD (quote_13): 0x0000000000000000000000000000000000000000
     * ZAR/USD (quote_14): 0x0000000000000000000000000000000000000000
     * RUB/USD (quote_15): 0x0000000000000000000000000000000000000000
     * INR/USD (quote_16): 0x0000000000000000000000000000000000000000
     * BRL/USD (quote_17): 0x04b7384473A2aDF1903E3a98aCAc5D62ba8C2702
     */

    constructor(){
        _priceFeeds[_currencies[0]] = AggregatorV3Interface(
            0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612
        );
        _priceFeeds[_currencies[1]] = AggregatorV3Interface(
            0x9C4424Fd84C6661F97D8d6b3fc3C1aAc2BeDd137
        );
        _priceFeeds[_currencies[2]] = AggregatorV3Interface(
            0xA14d53bC1F1c0F31B4aA3BD109344E5009051a84
        );
        _priceFeeds[_currencies[3]] = AggregatorV3Interface(
            0x3dD6e51CB9caE717d5a8778CF79A04029f9cFDF8
        );
        _priceFeeds[_currencies[4]] = AggregatorV3Interface(
            0x85bb02E0Ae286600d1c68Bb6Ce22Cc998d411916
        );
        _priceFeeds[_currencies[5]] = AggregatorV3Interface(
            0xcC3370Bde6AFE51e1205a5038947b9836371eCCb
        );
        _priceFeeds[_currencies[6]] = AggregatorV3Interface(
            0x9854e9a850e7C354c1de177eA953a6b1fba8Fc22
        );
        _priceFeeds[_currencies[7]] = AggregatorV3Interface(
            0xf6DA27749484843c4F02f5Ad1378ceE723dD61d4
        );
        _priceFeeds[_currencies[8]] = AggregatorV3Interface(
            0xe32AccC8c4eC03F6E75bd3621BfC9Fbb234E1FC3
        );
        _priceFeeds[_currencies[10]] = AggregatorV3Interface(
            0xfF82AAF635645fD0bcc7b619C3F28004cDb58574
        );
        _priceFeeds[_currencies[12]] = AggregatorV3Interface(
            0xF0d38324d1F86a176aC727A4b0c43c9F9d9c5EB1
        );
        _priceFeeds[_currencies[17]] = AggregatorV3Interface(
            0x04b7384473A2aDF1903E3a98aCAc5D62ba8C2702
        );
    }

    function _setPriceFeed(uint seq, address _feed) internal {
        _priceFeeds[_currencies[seq]] = AggregatorV3Interface(_feed);
    }

    function getPriceFeed(uint seq) external view returns (address) {
        return address(_priceFeeds[_currencies[seq]]);
    }

    function decimals(address quote) public view returns (uint8) {
        return _priceFeeds[quote].decimals();
    }

    function getCentPriceInWei(uint seq) public view returns (uint) {

        (int base, uint8 dec) = _getLatestPrice(0);

        if (seq == 0) {
            
            return 10 ** uint(16 + dec) / uint(base);

        } else if (seq <= 17){

            (int quote, uint8 quoteDec) = _getLatestPrice(seq);
            quote = _scalePrice(quote, quoteDec, dec);

            return 10 ** uint(16 + dec) * uint(quote) / uint(base);

        } else revert("seqOfCurrency overflow");
    }

    function _getLatestPrice(uint seq) private view 
        returns(int price, uint8 dec) 
    {
        require(address(_priceFeeds[_currencies[seq]]) > address(0),
            "No Available PriceFeed");

        (
            /*uint80 roundID*/,
            price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = _priceFeeds[_currencies[seq]].latestRoundData();

        dec = _priceFeeds[_currencies[seq]].decimals();        
    }

    function _scalePrice(
        int256 _price,
        uint8 _priceDecimals,
        uint8 _decimals
    ) private pure returns (int256) {
        if (_priceDecimals < _decimals) {
            return _price * int256(10 ** uint(_decimals - _priceDecimals));
        } else if (_priceDecimals > _decimals) {
            return _price / int256(10 ** uint(_priceDecimals - _decimals));
        }
        return _price;
    }

}

