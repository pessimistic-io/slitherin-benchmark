// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {IRouter} from "./IRouter.sol";

library FlipLib {
    bytes32 constant FLIP_STORAGE_POSITION = keccak256("diamond.standard.flip.storage");

    struct FlipStorage {
        mapping(
            address
                => mapping(
                    uint256 => mapping(IRouter.OptionStrategy => mapping(IRouter.OptionStrategy => IRouter.FlipSignal))
                )
            ) userFlip;
        mapping(IRouter.OptionStrategy => mapping(IRouter.OptionStrategy => uint256)) flipSignals;
    }

    function flipStorage() internal pure returns (FlipStorage storage fs) {
        bytes32 position = FLIP_STORAGE_POSITION;
        assembly {
            fs.slot := position
        }
    }

    function flipSignals(IRouter.OptionStrategy _oldStrategy, IRouter.OptionStrategy _newStrategy)
        internal
        view
        returns (uint256)
    {
        return flipStorage().flipSignals[_oldStrategy][_newStrategy];
    }

    function userFlip(
        address _user,
        uint256 _epoch,
        IRouter.OptionStrategy _oldStrategy,
        IRouter.OptionStrategy _newStrategy
    ) internal view returns (IRouter.FlipSignal memory) {
        return flipStorage().userFlip[_user][_epoch][_oldStrategy][_newStrategy];
    }
}

