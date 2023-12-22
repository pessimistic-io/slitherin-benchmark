pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


/**
 * @title Epoch Library
 * @author Nevermined
 *
 * @dev Implementation of Epoch Library.
 *      For an arbitrary Epoch, this library manages the life
 *      cycle of an Epoch. Usually this library is used for 
 *      handling the time window between conditions in an agreement.
 */
library EpochLibrary {

    struct Epoch {
        uint256 timeLock;
        uint256 timeOut;
        uint256 blockNumber;
    }

    struct EpochList {
        mapping(bytes32 => Epoch) epochs;
    }

   /**
    * @notice isTimedOut means you cannot fulfill after
    * @param _self is the Epoch storage pointer
    * @return true if the current block number is gt timeOut
    */
    function isTimedOut(
        EpochList storage _self,
        bytes32 _id
    )
        internal
        view
        returns (bool)
    {
        if (_self.epochs[_id].timeOut == 0) {
            return false;
        }

        return (block.number > getEpochTimeOut(_self.epochs[_id]));
    }

   /**
    * @notice isTimeLocked means you cannot fulfill before
    * @param _self is the Epoch storage pointer
    * @return true if the current block number is gt timeLock
    */
    function isTimeLocked(
        EpochList storage _self,
        bytes32 _id
    )
        internal
        view
        returns (bool)
    {
        return (block.number < getEpochTimeLock(_self.epochs[_id]));
    }

   /**
    * @notice getEpochTimeOut
    * @param _self is the Epoch storage pointer
    */
    function getEpochTimeOut(
        Epoch storage _self
    )
        internal
        view
        returns (uint256)
    {
        return _self.timeOut + _self.blockNumber;
    }

    /**
    * @notice getEpochTimeLock
    * @param _self is the Epoch storage pointer
    */
    function getEpochTimeLock(
        Epoch storage _self
    )
        internal
        view
        returns (uint256)
    {
        return _self.timeLock + _self.blockNumber;
    }
}

