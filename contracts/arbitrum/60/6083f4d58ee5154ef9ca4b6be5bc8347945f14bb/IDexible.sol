//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./SwapTypes.sol";

interface IDexible {

    event SwapFailed(address indexed trader, 
                     IERC20 feeToken, 
                     uint gasFeePaid);
    event SwapSuccess(address indexed trader,
                        address indexed affiliate,
                        uint inputAmount,
                        uint outputAmount,
                        IERC20 feeToken,
                        uint gasFee,
                        uint affiliateFee,
                        uint dexibleFee);
    event AffiliatePaid(address indexed affiliate, IERC20 token, uint amount);

    event PaidGasFunds(address indexed relay, uint amount);
    event InsufficientGasFunds(address indexed relay, uint amount);
    event ChangedRevshareVault(address indexed old, address indexed newRevshare);
    event ChangedRevshareSplit(uint8 split);
    event ChangedBpsRates(uint32 stdRate, uint32 minRate);

    function setTreasury(address t) external;
    function swap(SwapTypes.SwapRequest calldata request) external;
    function selfSwap(SwapTypes.SelfSwap calldata request) external;
    
}
