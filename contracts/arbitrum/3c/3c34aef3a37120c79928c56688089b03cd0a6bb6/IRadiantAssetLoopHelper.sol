// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IRadiantAssetLoopHelper {
    function totalStaked(address _asset) external view returns (uint256);

    function balance(address _asset, address _address) external view returns (uint256);

    function loopAsset(
        address _asset,
        uint256 _amount
    ) external payable;

    function loopAssetFor(
        address _asset,
        address _for,
        uint256 _amount
    ) external payable;

    function withdrawAsset(address _asset, uint256 _amount) external;

    function harvest(address _asset) external;

    function setPoolInfo(
        address poolAddress,
        address rewarder,
        bool isNative,
        bool isActive
    ) external;

    function setOperator(address _address, bool _value) external;
}

