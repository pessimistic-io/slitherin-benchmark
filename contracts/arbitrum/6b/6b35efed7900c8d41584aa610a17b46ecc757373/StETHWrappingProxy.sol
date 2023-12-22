// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import { IERC20 } from "./IERC20.sol";
import { SafeCast } from "./SafeCast.sol";

import { IDCSEntry } from "./IDCSEntry.sol";
import { IWrappingProxy } from "./IWrappingProxy.sol";
import { IWstETH } from "./IWstETH.sol";

contract StETHWrappingProxy is IWrappingProxy {
    using SafeCast for uint256;

    IDCSEntry public immutable cegaEntry;

    IERC20 public immutable stETH;

    IWstETH public immutable wstETH;

    constructor(IDCSEntry _cegaEntry, IERC20 _stETH, IWstETH _wstETH) {
        cegaEntry = _cegaEntry;
        stETH = _stETH;
        wstETH = _wstETH;

        // stETH and wstETH support infinite approval, so it's enough to approve once
        _stETH.approve(address(_wstETH), type(uint256).max);
        _wstETH.approve(address(_cegaEntry), type(uint256).max);
    }

    function unwrapAndTransfer(address receiver, uint256 amount) external {
        uint256 stETHAmount = wstETH.unwrap(amount);
        stETH.transfer(receiver, stETHAmount);
    }

    function wrapAndAddToDCSDepositQueue(
        uint32 productId,
        uint128 amount,
        address receiver
    ) external {
        stETH.transferFrom(msg.sender, address(this), amount);
        uint128 wstETHAmount = wstETH.wrap(amount).toUint128();
        cegaEntry.dcsAddToDepositQueue(productId, wstETHAmount, receiver);
    }
}

