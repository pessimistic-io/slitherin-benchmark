// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./IERC20.sol";

interface IVeArken is IERC20 {
    function isTransferWhitelisted(
        address account
    ) external view returns (bool);
}

