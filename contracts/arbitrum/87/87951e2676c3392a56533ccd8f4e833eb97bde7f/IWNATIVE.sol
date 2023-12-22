// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20} from "./IERC20.sol";

/**
 * @title WAVAX Interface
 * @notice Required interface of Wrapped AVAX contract
 */
interface IWNATIVE is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}
