// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface IZapDashboard {
    function estimatedReceiveLpData(address _token, uint256 _amount) external view returns (uint256, uint256);
    function getLiquidityInfo(
        address token,
        uint256 tokenAmount
    ) external view returns (uint256, uint256);

    function getTokenAmount(
        uint256 tokenAmount
    ) external view returns (uint256, uint256);
}

