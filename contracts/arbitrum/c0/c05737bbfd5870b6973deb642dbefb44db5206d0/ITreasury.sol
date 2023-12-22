// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity =0.8.18;

interface ITreasury {
    function addDebt(address token, uint256 amount) external;

    function repayDebt(address token, uint256 amount) external;
}

