// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBFRRouter {
    function stakeBfr(uint256 amount) external;
    function unstakeBfr(uint256 amount) external;
    function compound() external;
    function claimFees() external;
    function mintAndStakeBlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minBlp
    ) external returns (uint256);
    function unstakeAndRedeemBlp(
        address _tokenOut,
        uint256 _blpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);
    function feeBlpTracker() external view returns (address);
    function feeBfrTracker() external view returns (address);
    function stakedBfrTracker() external view returns (address);
    function blpManager() external view returns (address);
    function blp() external view returns (address);
    function signalTransfer(address _receiver) external;
    function acceptTransfer(address _sender) external;
}

