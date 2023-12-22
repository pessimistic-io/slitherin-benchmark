// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBooster {
    function depositInGauge(address pool, uint amount) external;

    function withdrawFromGauge(address pool, uint amount) external;

    function getRewardFromGauge(
        address pool,
        address[] calldata tokens
    ) external;

    function claimBribes(
        address pool
    ) external returns (address[] memory bribes);

    function poke(address token) external;

    function setTokenForPool(address pool, address token) external;

    function gaugeForPool(address pool) external view returns (address gauge);

    function voter() external view returns (address);

    function tokenID() external view returns (uint);

    function ram() external view returns (address);

    function veDepositor() external view returns (address);

    function earned(
        address pool,
        address token
    ) external view returns (uint rewards);

    function setFee(uint fee) external;

    function feeHandler() external view returns (address);

    function platformFee() external view returns (uint);

    function treasuryFee() external view returns (uint);

    function stakerFee() external view returns (uint);

    function neadRam() external view returns (address);

    function xRam() external view returns (address);
}

