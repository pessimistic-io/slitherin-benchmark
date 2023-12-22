// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IGLPPool {

    function stakeByGov(
        address _token, 
        uint256 _amount, 
        uint256 _minUsdg, 
        uint256 _minGlp
    ) external;

    function withdrawByGov(
        address _tokenOut, 
        uint256 _glpAmount, 
        uint256 _minOut, 
        address _receiver
    ) external;

    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;

    function total_supply_staked() external returns (uint256);

    function handleStakeRequest(address[] memory _address) external;

    function handleWithdrawRequest(address[] memory _address) external;

    function allocateReward(int256 _amount) external;

    function setGlpFee(uint256 _glpInFee, uint256 _glpOutFee) external;

    function setCapacity(uint256 _amount) external;

    function resetCurrentEpochReward() external;

    function treasuryWithdrawFunds(address token, uint256 amount, address to) external;

    function treasuryWithdrawFundsETH(uint256 amount, address to) external;

    function getStakedGLPUSDValue(bool _maximum) external view returns (uint256);

    function getRequiredCollateral() external view returns (uint256);

    function pause() external;

    function unpause() external;
}    
    
