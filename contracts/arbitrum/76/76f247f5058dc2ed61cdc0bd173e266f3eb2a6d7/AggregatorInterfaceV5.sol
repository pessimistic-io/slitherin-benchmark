// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface AggregatorInterfaceV5{
    enum OrderType { MARKET_OPEN, MARKET_CLOSE, LIMIT_OPEN, LIMIT_CLOSE }
    function getPrice(uint,OrderType,uint) external returns(uint);
    function tokenPriceDai() external view returns(uint);
    function pairMinOpenLimitSlippageP(uint) external view returns(uint);
    function closeFeeP(uint) external view returns(uint);
    function linkFee(uint,uint) external view returns(uint);
    function openFeeP(uint) external view returns(uint);
    function pairMinLeverage(uint) external view returns(uint);
    function pairMaxLeverage(uint) external view returns(uint);
    function pairsCount() external view returns(uint);
    function tokenDaiReservesLp() external view returns(uint, uint);
    function referralP(uint) external view returns(uint);
    function nftLimitOrderFeeP(uint) external view returns(uint);
}
