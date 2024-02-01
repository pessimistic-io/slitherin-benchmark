// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

interface IVestingFactory {
    function treasury() external returns (address);

    function token() external returns (IERC20);

    function changeRecipient(address _oldRecipient, address _newRecipient) external;
}

