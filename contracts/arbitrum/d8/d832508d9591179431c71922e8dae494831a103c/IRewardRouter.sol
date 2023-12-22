// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./ReentrancyGuard.sol";

interface IRewardRouter {
    function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
    function mintAndStakeGlpETH(uint256 _minUsdg, uint256 _minGlp) external payable returns (uint256);
    function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external returns (uint256);
    function unstakeAndRedeemGlpETH(uint256 _glpAmount, uint256 _minOut, address payable _receiver) external returns (uint256);
    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;
}


