// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ISubstitute} from "./ISubstitute.sol";

interface IAaveTokenSubstitute is ISubstitute {
    function aToken() external view returns (address);

    function mintByAToken(uint256 amount, address to) external;

    function burnToAToken(uint256 amount, address to) external;
}

