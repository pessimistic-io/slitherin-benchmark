// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICurveStrategyXChain {
    function toggleVault(address _vaultAddress) external;

    function setCurveGauge(address _vaultLpToken, address _crvGaugeAddress) external;

	function setSdGauge(address _crvGaugeAddress, address _gaugeAddress) external;

    function setRewardsReceiver(address _crvGaugeAddress, address _rewardReceiver) external;

    function deposit(address _user, uint256 _amount) external;
    
    function withdraw(address _user, uint256 _amount) external;

    function claim(address _lpToken) external;

    function claims(address[] calldata _lpTokens) external;
}
