// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./IERC20.sol";
import {IIncentiveController} from "./IIncentive.sol";
import {IAnyswapV4Token} from "./IAnyswapV4Token.sol";

interface INUON is IERC20, IAnyswapV4Token {
    function mint(address who, uint256 amount) external;

    function setNUONController(address _controller) external;

    function burn(uint256 amount) external;
}

