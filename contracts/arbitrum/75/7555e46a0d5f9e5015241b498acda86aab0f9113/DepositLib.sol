// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {IRouter} from "./IRouter.sol";

library DepositLib {
    /**
     * @notice Deposit storage position.
     */
    bytes32 constant DEPOSIT_STORAGE_POSITION = keccak256("diamond.standard.deposit.storage");

    /**
     * @notice Deposit storage.
     */
    struct DepositStorage {
        mapping(IRouter.OptionStrategy => uint256) nextEpochDeposits;
        mapping(address => mapping(uint256 => mapping(IRouter.OptionStrategy => uint256))) userNextEpochDeposits;
    }

    /**
     * @notice Get deposit storage.
     */
    function depositStorage() internal pure returns (DepositStorage storage ds) {
        bytes32 position = DEPOSIT_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    /**
     * @notice Total strategy next epoch deposit.
     */
    function nextEpochDeposits(IRouter.OptionStrategy _strategy) internal view returns (uint256) {
        return depositStorage().nextEpochDeposits[_strategy];
    }

    /**
     * @notice User next epoch deposit for a strategy.
     */
    function userNextEpochDeposits(address _user, uint256 _epoch, IRouter.OptionStrategy _strategy)
        internal
        view
        returns (uint256)
    {
        return depositStorage().userNextEpochDeposits[_user][_epoch][_strategy];
    }
}

