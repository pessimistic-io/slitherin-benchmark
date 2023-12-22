// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;
import { IERC20 } from "./IERC20.sol";

import { IAmm } from "./IAmm.sol";

interface IInsuranceFund {
    function withdraw(IAmm _amm, uint256 _amount) external;

    function deposit(IAmm _amm, uint256 _amount) external;

    function isExistedAmm(IAmm _amm) external view returns (bool);

    function getAllAmms() external view returns (IAmm[] memory);

    function getAvailableBudgetFor(IAmm _amm) external view returns (uint256);
}

