// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IEntityFactory {
    
    event EntityCreated(address _entityAddress);
    event OnboarderSet(address oldOnboarder, address onboarder);

    function createEntity(bytes memory _creationData) external returns(address);

}
