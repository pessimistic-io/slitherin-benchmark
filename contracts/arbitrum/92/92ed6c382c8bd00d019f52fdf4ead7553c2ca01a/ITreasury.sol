// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";


interface ITreasury {
    struct StreamInfo {
        uint256 totalFund;
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 lastPullTimestamp;
        uint256 ratePerSecond;
        uint256 funded;
    }
    
    function requestFund() external returns (uint256 rewardsPaid);

    function grantTokenToStream(address _stream, uint256 _amount) external;

    function getStreams() external view returns (address[] memory);

    function getStreamInfo(address _stream) external view returns (StreamInfo memory);

    function getGlobalRatePerSecond() external view returns (uint256 globalRatePerSecond);

    function getRatePerSecond(address _stream) external view returns (uint256 ratePerSecond);

    function getPendingFund(address _stream) external view returns (uint256 pendingFund);
}
