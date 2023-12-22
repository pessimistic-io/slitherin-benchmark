//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface IWombatPoolHelper {
    function totalStaked() external view returns (uint256);

    function balance(address _address) external view returns (uint256);

    function depositToken() external view returns (address);
    
    function lpToken() external view returns (address);

    function rewarder() external view returns (address);

    function masterMagpie() external view returns (address);

    function stakingToken() external view returns (address);

    function wombatStaking() external view returns (address);

    function deposit(uint256 amount, uint256 minimumAmount) external;

    function withdraw(uint256 amount, uint256 minimumAmount) external;

    function depositNative(uint256 _minimumLiquidity) external payable;

    function depositLP(uint256 _lpAmount) external;

    function withdrawLP(uint256 _lpAmount, bool _harvest) external;

    function harvest() external;
}

