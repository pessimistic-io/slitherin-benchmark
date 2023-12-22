// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

interface IVoter {
    function gauges(address) external returns (address);
}
