// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Proxied} from "./Proxied.sol";
import {     GelatoRelayFeeCollector } from "./GelatoRelayFeeCollector.sol";
import {Address} from "./Address.sol";
import {_isGelatoRelayDev} from "./IsGelatoRelayDev.sol";

// Inheriting GelatoRelayFeeCollector gives access to:
// 1. _getFeeCollector(): returns the address of Gelato's feeCollector
// 2. __msgData(): returns the original msg.data without feeCollector appended
// 3. onlyGelatoRelay modifier: allows only Gelato Relay's smart contract to call the function
contract CounterFeeCollector is Proxied, GelatoRelayFeeCollector {
    using Address for address payable;

    uint256 public counter;

    // solhint-disable-next-line var-name-mixedcase
    bool public immutable IS_DEV_ENV;

    event GetBalance(uint256 balance);
    event IncrementCounter(uint256 newCounterValue);

    constructor(bool _isDevEnv) {
        IS_DEV_ENV = _isDevEnv;
    }

    // `increment` is the target function to call
    // this function increments the state variable `counter` by 1
    // Payment to Gelato
    // NOTE: be very careful here!
    // if you do not use the onlyGelatoRelay modifier,
    // anyone could encode themselves as the fee collector
    // in the low-level data and drain tokens from this contract.
    function increment(uint256 _fee) external {
        // Checks
        if (IS_DEV_ENV) {
            require(
                _isGelatoRelayDev(msg.sender),
                "CounterFeeCollector.increment: isGelatoRelayDev"
            );
        } else {
            require(
                _isGelatoRelay(msg.sender),
                "CounterFeeCollector.increment: isGelatoRelay"
            );
        }

        // Effects
        counter++;

        // Interactions
        payable(_getFeeCollector()).sendValue(_fee);

        emit IncrementCounter(counter);
    }

    function emptyBalance() external onlyProxyAdmin {
        payable(msg.sender).sendValue(address(this).balance);
    }

    function getBalance() external {
        emit GetBalance(address(this).balance);
    }
}

