//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGambitStakingV1 {
    function storageT() external view returns (address);

    function token() external view returns (address);

    function usdc() external view returns (address);

    function accUsdcPerToken() external view returns (uint /* 1e18 */);

    function tokenBalance() external view returns (uint /* 1e18 */);

    function distributeRewardUsdc(
        uint amount // 1e6
    ) external;
}

