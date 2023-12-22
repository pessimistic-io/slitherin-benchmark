// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";

interface IVault is IERC20 {
    function token() external view returns (address);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function governance() external view returns (address);

    function getPricePerFullShare() external view returns (uint256);

    function deposit(uint256) external;

    function depositAll() external;

    function withdraw(uint256) external;

    function withdrawAll() external;

    function pricePerShare() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function earn() external view;
}

