// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IPriceEvents {
    function emitPriceEvent(address _token, uint256 _price) external;
}

