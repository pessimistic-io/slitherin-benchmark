
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./SimpleRewardPool.sol";

/// @title  SimpleRewardPoolFactory
/// @notice create a SimpleRewardPool instance from function create then set address to staking pool
contract SimpleRewardPoolFactory {
    IAdminAccess public adminAccess;
    event SimpleRewardPoolCreatedEvent(address creator, address newRewardPool);
    modifier atLeastAdmin() {
        require(adminAccess.hasAdminRole(msg.sender)||(adminAccess.getOwner() == msg.sender), "!auth");
        _;
    }
    constructor(address _accessController) {
        adminAccess=IAdminAccess(_accessController);
    }

    /// @notice create
    /// @dev instance address can be find at event log when test manually
    /// @param stakingToken, ERC20 address of staking token
    /// @param stakingPool, contract address of staking pool
    /// @return Returns address of instance.
    function create(address stakingToken,address stakingPool) public atLeastAdmin returns(address){
        SimpleRewardPool rewardPool = new SimpleRewardPool(stakingToken,stakingPool,address(adminAccess));
        emit SimpleRewardPoolCreatedEvent(msg.sender, address(rewardPool));
        return address(rewardPool);
    }

}
