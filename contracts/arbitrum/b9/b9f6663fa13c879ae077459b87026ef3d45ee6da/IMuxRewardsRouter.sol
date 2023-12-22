// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

interface IMuxRewardsRouter {
    function stakeMlp(uint256 _amount) external returns (uint256);
    function unstakeMlp(uint256 _amount) external returns (uint256);
    function claimFromMlpUnwrap() external;
    function claimAllUnwrap() external;
    function claimFromMlp() external;
}

