// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0 <0.8.0;

interface IPriceHelper {
    function getSlipPointPrice(string memory token, uint256 price, uint256 value, uint256 maxValue, bool maximise) external view returns (uint256);
}

