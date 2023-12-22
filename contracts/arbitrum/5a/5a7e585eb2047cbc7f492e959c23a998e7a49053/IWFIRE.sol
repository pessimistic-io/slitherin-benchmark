// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

interface IWFIRE {
    function deposit(uint256 fires) external returns (uint256);

    function burn(uint256 wfires) external returns (uint256);

    function MAX_WFIRE_SUPPLY() external view returns (uint256);
}

