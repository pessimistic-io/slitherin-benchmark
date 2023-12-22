// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import { Inflate } from "./Inflate.sol";

interface IInflator {
    function puff(bytes memory source, uint256 destlen) external pure returns (Inflate.ErrorCode, bytes memory);
}

