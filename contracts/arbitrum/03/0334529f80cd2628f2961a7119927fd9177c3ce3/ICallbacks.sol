// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICallbacks{
    struct AggregatorAnswer{ uint orderId; uint price; uint spreadP; }
    function usdtVaultFeeP() external view returns(uint);
    function lpFeeP() external view returns(uint);
    function sssFeeP() external view returns(uint);
    function MAX_SL_P() external view returns(uint);
    function MIN_SL_P() external view returns(uint);
    function MAX_GAIN_P() external view returns(uint);
    function MIN_GAIN_P() external view returns(uint);
    function openTradeMarketCallback(AggregatorAnswer memory) external;
    function closeTradeMarketCallback(AggregatorAnswer memory) external;
    function executeNftOpenOrderCallback(AggregatorAnswer memory) external;
    function executeNftCloseOrderCallback(AggregatorAnswer memory) external;
    function updateSlCallback(AggregatorAnswer memory) external;
    function withinExposureLimits(uint, bool, uint, uint) external view returns(bool);
    function adlSendToVault(uint, address) external;
    function adlVaultSendToTrader(uint, address ) external;
}
