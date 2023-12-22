// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface ILeverager {
    function getVDebtToken() external view returns (address);

    function getAToken() external view returns (address);
}

