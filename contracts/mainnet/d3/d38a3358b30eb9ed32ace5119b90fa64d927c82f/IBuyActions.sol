// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
import {ConsiderationInterface, Order} from "./ConsiderationInterface.sol";

interface IBuyActions {
    function buy(Order calldata seaportOrder) external;
}

