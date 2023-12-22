// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

interface IRebaser {
    function rebase(
        uint256 currentPrice, 
        uint256 targetPrice
    ) external returns (
        uint256 amountToSwap,
        uint256 amountUSDTtoAdd,
        uint256 burnAmount
    );
    function setTeamAddress(address _teamAddress) external;
    function setRebaseEnabled(bool flag) external;
    function setSwapPair(address _pair) external;
}
