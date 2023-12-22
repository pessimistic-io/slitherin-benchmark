// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Proxied} from "./Proxied.sol";
import {     GelatoRelayContext } from "./GelatoRelayContext.sol";
import {Address} from "./Address.sol";
import {_isGelatoRelayDev} from "./IsGelatoRelayDev.sol";

// Inheriting GelatoRelayContext gives access to:
// 1. _getFeeCollector(): returns the address of Gelato's feeCollector
// 2. _getFeeToken(): returns the address of the fee token
// 3. _getFee(): returns the fee to pay
// 4. _transferRelayFee(): transfers the required fee to Gelato's feeCollector.abi
// 5. _transferRelayFeeCapped(uint256 maxFee): transfers the fee to Gelato, IF fee < maxFee
// 6. __msgData(): returns the original msg.data without appended information
// 7. onlyGelatoRelay modifier: allows only Gelato Relay's smart contract to call the function
contract CounterRelayContext is Proxied, GelatoRelayContext {
    using Address for address payable;

    uint256 public counter;

    // solhint-disable-next-line var-name-mixedcase
    bool public immutable IS_DEV_ENV;

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
    function increment() external {
        // Checks
        if (IS_DEV_ENV) {
            require(
                _isGelatoRelayDev(msg.sender),
                "CounterRelayContext.increment: isGelatoRelayDev"
            );
        } else {
            require(
                _isGelatoRelay(msg.sender),
                "CounterRelayContext.increment: isGelatoRelay"
            );
        }

        // Effects
        counter++;

        // transfer fees to Gelato
        _transferRelayFee();

        emit IncrementCounter(counter);
    }

    function emptyBalance() external onlyProxyAdmin {
        payable(msg.sender).sendValue(address(this).balance);
    }
}

