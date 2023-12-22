//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;


import "./ERC20.sol";
import "./IRevshareEvents.sol";

interface IRevshareVault is IRevshareEvents {

    struct AssetInfo {
        address token;
        uint balance;
        uint usdValue;
        uint usdPrice;
    }

    function isFeeTokenAllowed(address tokens) external view returns (bool);
    function currentMintRateUSD() external view returns (uint);
    function currentNavUSD() external view returns(uint);
    function discountBps() external view returns(uint32);
    function dailyVolumeUSD() external view returns(uint);
    function aumUSD() external view returns(uint);
    function feeTokenPriceUSD(address feeToken) external view returns (uint);
    function convertGasToFeeToken(address feeToken, uint gasCost) external view returns (uint);
    function assets() external view returns (AssetInfo[] memory);
    function rewardTrader(address trader, address feeToken, uint amount) external;
    function estimateRedemption(address feeToken, uint dxblAmount) external view returns(uint);
    function redeemDXBL(address feeToken, uint dxblAmount, uint minOutAmount) external;
}
