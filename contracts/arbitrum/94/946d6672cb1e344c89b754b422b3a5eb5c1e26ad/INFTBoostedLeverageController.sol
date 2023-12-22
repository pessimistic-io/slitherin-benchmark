// SPDX-License-Identifier: MIT

pragma solidity 0.6.6;

interface INFTBoostedLeverageController {
    function getBoostedWorkFactor(
        address owner,
        address worker
    ) external view returns (uint64);

    function getBoostedKillFactor(
        address owner,
        address worker
    ) external view returns (uint64);
}

