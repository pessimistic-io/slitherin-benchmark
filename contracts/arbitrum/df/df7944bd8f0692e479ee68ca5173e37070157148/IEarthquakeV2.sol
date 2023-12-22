// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IEarthquakeV2 {
    function asset() external view returns (address asset);

    function token() external view returns (address token);

    function strike() external view returns (uint256 strike);

    function name() external view returns (string memory name);

    function symbol() external view returns (string memory symbol);

    function isWETH() external view returns (bool isWeth);
}

