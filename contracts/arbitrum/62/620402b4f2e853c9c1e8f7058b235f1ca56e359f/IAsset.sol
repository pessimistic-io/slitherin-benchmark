// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

// Primary Author(s)
// MAXOS Team: https://maxos.finance/

interface IAsset {
    function currentValue() external view returns (uint256);

    function isDefaulted() external view returns (bool);

    function deposit(uint256 usdx_amount, uint256 sweep_amount) external;

    function withdraw(uint256 amount) external;

    function updateValue(uint256 value) external;

    function withdrawRewards(address to) external;
}

