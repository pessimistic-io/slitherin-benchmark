// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./IERC20.sol";
import "./IBrightPoolLedger.sol";

interface IBrightPoolConsumer {
    function consume(IBrightPoolLedger.Asset memory asset_, uint256 affId_, address affRcpt_) external payable;
}

