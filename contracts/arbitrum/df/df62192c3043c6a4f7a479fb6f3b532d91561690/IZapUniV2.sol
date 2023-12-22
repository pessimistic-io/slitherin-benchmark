// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IRouter} from "./IRouter.sol";

interface IZapUniV2 {
    struct ZapParams {
        address pair;
        bool native;
        address tokenIn;
        uint256 amount;
        IRouter.OptionStrategy strategy;
        bool instant;
        bytes[] _optionOrders;
        bytes _signature;
    }

    function zapIn(ZapParams memory params) external payable returns (uint256);
    function setMetavault(address pair, address router, address swapper, address pairAdapter) external;
}

