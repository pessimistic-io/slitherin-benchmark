// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {IRouter} from "./IRouter.sol";

library FlipLib {
    /**
     * @notice Flip storage position.
     */
    bytes32 constant FLIP_STORAGE_POSITION = keccak256("diamond.standard.flip.storage");

    /**
     * @notice Flip storage.
     */
    struct FlipStorage {
        mapping(
            address
                => mapping(
                    uint256 => mapping(IRouter.OptionStrategy => mapping(IRouter.OptionStrategy => IRouter.FlipSignal))
                )
            ) userFlip;
        mapping(IRouter.OptionStrategy => mapping(IRouter.OptionStrategy => uint256)) flipSignals;
    }

    /**
     * @notice Flip deposit storage.
     */
    function flipStorage() internal pure returns (FlipStorage storage fs) {
        bytes32 position = FLIP_STORAGE_POSITION;
        assembly {
            fs.slot := position
        }
    }

    /**
     * @notice Total Flip Signals.
     */
    function flipSignals(IRouter.OptionStrategy _oldStrategy, IRouter.OptionStrategy _newStrategy)
        internal
        view
        returns (uint256)
    {
        return flipStorage().flipSignals[_oldStrategy][_newStrategy];
    }

    /**
     * @notice User flip signals.
     */
    function userFlip(
        address _user,
        uint256 _epoch,
        IRouter.OptionStrategy _oldStrategy,
        IRouter.OptionStrategy _newStrategy
    ) internal view returns (IRouter.FlipSignal memory) {
        return flipStorage().userFlip[_user][_epoch][_oldStrategy][_newStrategy];
    }
}

