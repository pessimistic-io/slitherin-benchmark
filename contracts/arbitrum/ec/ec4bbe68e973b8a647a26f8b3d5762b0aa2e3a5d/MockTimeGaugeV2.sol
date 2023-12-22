// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "./GaugeV2.sol";

interface IMockTimeRamsesV2Pool {
    function time() external view returns (uint256 _time);
}

contract MockTimeGaugeV2 is GaugeV2 {
    function _blockTimestamp() internal view override returns (uint256) {
        return IMockTimeRamsesV2Pool(address(pool)).time();
    }
}

