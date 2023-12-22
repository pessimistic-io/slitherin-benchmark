// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IRadiantStaking {
    function getTotalLocked() external view returns (uint256);

    function zapNative(address _for) external payable returns (uint256 liquidity);

    function stakeLp(uint256 _amount) external;

    function zapRdnt(address _for, uint256 _amount) external payable returns (uint256 liquidity);

    // function loopAsset(
    //     address _asset,
    //     address _for,
    //     address _from,
    //     uint256 _amount,
    //     bool _isNative
    // ) external payable;

    // function withdrawAsset(address _asset, address _for, uint256 _amount) external;

    // function harvestAssetReward(address _lpAddress) external;
}

