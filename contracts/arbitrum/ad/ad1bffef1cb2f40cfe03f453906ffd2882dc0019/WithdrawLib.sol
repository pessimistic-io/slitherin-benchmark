// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {IRouter} from "./IRouter.sol";

library WithdrawLib {
    bytes32 constant WITHDRAW_STORAGE_POSITION = keccak256("diamond.standard.withdraw.storage");

    struct WithdrawStorage {
        mapping(IRouter.OptionStrategy => uint256) withdrawSignals;
        mapping(address => mapping(uint256 => mapping(IRouter.OptionStrategy => IRouter.WithdrawalSignal))) userSignal;
    }

    function withdrawStorage() internal pure returns (WithdrawStorage storage ws) {
        bytes32 position = WITHDRAW_STORAGE_POSITION;
        assembly {
            ws.slot := position
        }
    }

    function withdrawSignals(IRouter.OptionStrategy _strategy) internal view returns (uint256) {
        return withdrawStorage().withdrawSignals[_strategy];
    }

    function userSignal(address _user, uint256 _epoch, IRouter.OptionStrategy _strategy)
        internal
        view
        returns (IRouter.WithdrawalSignal memory)
    {
        return withdrawStorage().userSignal[_user][_epoch][_strategy];
    }
}

