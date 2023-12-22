pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


/**
 * @title Condition Store Library
 * @author Nevermined
 *
 * @dev Implementation of the Condition Store Library.
 *      
 *      Condition is a key component in the service execution agreement. 
 *      This library holds the logic for creating and updating condition 
 *      Any Condition has only four state transitions starts with Uninitialized,
 *      Unfulfilled, Fulfilled, and Aborted. Condition state transition goes only 
 *      forward from Unintialized -> Unfulfilled -> {Fulfilled || Aborted} 
 */
library ConditionStoreLibrary {

    enum ConditionState { Uninitialized, Unfulfilled, Fulfilled, Aborted }

    struct Condition {
        address typeRef;
        ConditionState state;
    }

    struct ConditionList {
        mapping(bytes32 => Condition) conditions;
        mapping(bytes32 => mapping(bytes32 => bytes32)) map;
    }
    
    
   /**
    * @notice create new condition
    * @dev check whether the condition exists, assigns 
    *       condition type, condition state, last updated by, 
    *       and update at (which is the current block number)
    * @param _self is the ConditionList storage pointer
    * @param _id valid condition identifier
    * @param _typeRef condition contract address
    */
    function create(
        ConditionList storage _self,
        bytes32 _id,
        address _typeRef
    )
        internal
    {
        require(
            _self.conditions[_id].typeRef == address(0),
            'Id already exists'
        );

        _self.conditions[_id].typeRef = _typeRef;
        _self.conditions[_id].state = ConditionState.Unfulfilled;
    }

    /**
    * @notice updateState update the condition state
    * @dev check whether the condition state transition is right,
    *       assign the new state, update last updated by and
    *       updated at.
    * @param _self is the ConditionList storage pointer
    * @param _id condition identifier
    * @param _newState the new state of the condition
    */
    function updateState(
        ConditionList storage _self,
        bytes32 _id,
        ConditionState _newState
    )
        internal
    {
        require(
            _self.conditions[_id].state == ConditionState.Unfulfilled &&
            _newState > _self.conditions[_id].state,
            'Invalid state transition'
        );

        _self.conditions[_id].state = _newState;
    }
    
    function updateKeyValue(
        ConditionList storage _self,
        bytes32 _id,
        bytes32 _key,
        bytes32 _value
    )
    internal
    {
        _self.map[_id][_key] = _value;
    }
}

