// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Proxied} from "./Proxied.sol";
import {     GelatoRelayContextERC2771,     _getMsgSenderRelayContextERC2771 } from "./GelatoRelayContextERC2771.sol";
import {Address} from "./Address.sol";
import {_isGelatoRelayERC2771Dev} from "./IsGelatoRelayDev.sol";

// Inheriting GelatoRelayContext gives access to:
// 1. _getFeeCollector(): returns the address of Gelato's feeCollector
// 2. _getFeeToken(): returns the address of the fee token
// 3. _getFee(): returns the fee to pay
// 4. _transferRelayFee(): transfers the required fee to Gelato's feeCollector.abi
// 5. _transferRelayFeeCapped(uint256 maxFee): transfers the fee to Gelato, IF fee < maxFee
// 6. __msgData(): returns the original msg.data without appended information
// 7. onlyGelatoRelay modifier: allows only Gelato Relay's smart contract to call the function
contract CounterRelayContextERC2771 is Proxied, GelatoRelayContextERC2771 {
    using Address for address payable;

    uint256 public counter;

    // solhint-disable-next-line var-name-mixedcase
    bool public immutable IS_DEV_ENV;

    event IncrementCounter(uint256 newCounterValue, address msgSender);

    constructor(bool _isDevEnv) {
        IS_DEV_ENV = _isDevEnv;
    }

    // `increment` is the target function to call
    // this function increments the state variable `counter` by 1
    // Payment to Gelato
    // NOTE: be very careful here!
    // if you do not use the onlyGelatoRelayERC2771 modifier,
    // anyone could encode themselves as the fee collector
    // in the low-level data and drain tokens from this contract.
    function increment() external {
        // Checks
        if (IS_DEV_ENV) {
            require(
                _isGelatoRelayERC2771Dev(msg.sender),
                "CounterRelayContextERC2771.increment: isGelatoRelayERC2771Dev"
            );
        } else {
            require(
                _isGelatoRelayERC2771(msg.sender),
                "CounterRelayContextERC2771.increment: isGelatoRelayERC2771"
            );
        }

        // Effects
        counter++;

        // transfer fees to Gelato
        _transferRelayFee();

        emit IncrementCounter(
            counter,
            IS_DEV_ENV ? _getMsgSenderDevEnv() : _getMsgSender()
        );
    }

    function emptyBalance() external onlyProxyAdmin {
        payable(msg.sender).sendValue(address(this).balance);
    }

    function _getMsgSenderDevEnv() internal view returns (address) {
        return
            _isGelatoRelayERC2771Dev(msg.sender)
                ? _getMsgSenderRelayContextERC2771()
                : msg.sender;
    }
}

