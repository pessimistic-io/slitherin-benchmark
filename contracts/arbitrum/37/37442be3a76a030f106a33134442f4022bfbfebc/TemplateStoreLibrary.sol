pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


/**
 * @title Template Store Library
 * @author Nevermined
 *
 * @dev Implementation of the Template Store Library.
 *      
 *      Templates are blueprints for modular SEAs. When 
 *      creating an Agreement, a templateId defines the condition 
 *      and reward types that are instantiated in the ConditionStore.
 */
library TemplateStoreLibrary {

    enum TemplateState {
        Uninitialized,
        Proposed,
        Approved,
        Revoked
    }

    struct Template {
        TemplateState state;
        address owner;
        address lastUpdatedBy;
        uint256 blockNumberUpdated;
    }

    struct TemplateList {
        mapping(address => Template) templates;
        address[] templateIds;
    }

   /**
    * @notice propose new template
    * @param _self is the TemplateList storage pointer
    * @param _id proposed template contract address 
    * @return size which is the index of the proposed template
    */
    function propose(
        TemplateList storage _self,
        address _id,
        address _sender
    )
        internal
        returns (uint size)
    {
        require(
            _self.templates[_id].state == TemplateState.Uninitialized,
            'TemplateId already initialized'
        );

        _self.templates[_id] = Template({
            state: TemplateState.Proposed,
            owner: _sender,
            lastUpdatedBy: _sender,
            blockNumberUpdated: block.number
        });

        _self.templateIds.push(_id);

        return _self.templateIds.length;
    }

   /**
    * @notice approve new template
    * @param _self is the TemplateList storage pointer
    * @param _id proposed template contract address
    */
    function approve(
        TemplateList storage _self,
        address _id,
        address _sender
    )
        internal
    {
        require(
            _self.templates[_id].state == TemplateState.Proposed,
            'Template not Proposed'
        );

        _self.templates[_id].state = TemplateState.Approved;
        _self.templates[_id].lastUpdatedBy = _sender;
        _self.templates[_id].blockNumberUpdated = block.number;
    }

   /**
    * @notice revoke new template
    * @param _self is the TemplateList storage pointer
    * @param _id approved template contract address
    */
    function revoke(
        TemplateList storage _self,
        address _id,
        address _sender
    )
        internal
    {
        require(
            _self.templates[_id].state == TemplateState.Approved,
            'Template not Approved'
        );

        _self.templates[_id].state = TemplateState.Revoked;
        _self.templates[_id].lastUpdatedBy = _sender;
        _self.templates[_id].blockNumberUpdated = block.number;
    }
}

