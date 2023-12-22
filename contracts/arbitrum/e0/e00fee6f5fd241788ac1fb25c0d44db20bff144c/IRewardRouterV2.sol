// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IRewardRouterV2 {

    function gmx() external view returns (address);
    function esGmx() external view returns (address);
    function bnGmx() external view returns (address);
    function glp() external view returns (address);
    function stakedGmxTracker() external view returns (address);
    function bonusGmxTracker() external view returns (address);
    function feeGmxTracker() external view returns (address);    
    function feeGlpTracker() external view returns (address);
    function stakedGlpTracker() external view returns (address);
    function glpManager() external view returns (address);
    function weth() external view returns (address);
    function claim() external;
    function claimEsGmx() external;
    function claimFees() external;
    function signalTransfer(address _destination) external;

    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;

    function compound() external;
    function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);

    function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external returns (uint256);
}
