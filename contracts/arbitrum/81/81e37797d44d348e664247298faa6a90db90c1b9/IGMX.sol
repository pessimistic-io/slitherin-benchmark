// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGlpManager {
    function getAumInUsdg(bool) external view returns (uint256);
    function glp() external view returns (address);
    function vault() external view returns (address);
    function getPrice(bool _maximise) external view returns (uint256);
    function PRICE_PRECISION() external view returns (uint256);
}

interface IRewardRouter {
    function glpManager() external view returns (address);
    function feeGlpTracker() external view returns (address);
    function stakedGlpTracker() external view returns (address);
    function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
    function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external returns (uint256);
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

