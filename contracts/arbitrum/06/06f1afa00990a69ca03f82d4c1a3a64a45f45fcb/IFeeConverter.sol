// SPDX-License-Identifier: UNLICENSE
pragma solidity ^0.8.21;

import {IERC20} from "./IERC20.sol";
import {Ownable} from "./Ownable.sol";
import {ICamelotRouter} from "./ICamelotRouter.sol";

interface IFeeConverter {
    function setFeeToken(address _feeToken) external;
    function setRouter(address _router) external;
    function setUsdc(address _usdc) external;

    // Withdraw collected oracle fees to a recipient
    function withdrawFees() external;
    function convertFees() external payable returns (bool);
}

