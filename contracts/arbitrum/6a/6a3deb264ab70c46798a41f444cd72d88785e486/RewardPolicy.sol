pragma solidity ^0.8.0;

import "./Kernel.sol";

import { ERC20 } from "./ERC20.sol";

// Module dependencies
import { REWRD } from "./REWRD.sol";
import { ROLES } from "./ROLES.sol";
import { IxGMBLTokenUsage } from "./IxGMBLTokenUsage.sol";

contract RewardPolicy is Policy {
    REWRD public rewrd;
    ROLES public roles;

    constructor(Kernel kernel_) Policy(kernel_) {}

    modifier OnlyOwner {
        roles.requireRole("rewardsmanager", msg.sender);
        _;
    }

    function configureDependencies() external override onlyKernel returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("REWRD");
        dependencies[1] = toKeycode("ROLES");

        rewrd = REWRD(getModuleAddress(dependencies[0]));
        roles = ROLES(getModuleAddress(dependencies[1]));
    }

    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        Keycode REWRD_KEYCODE = toKeycode("REWRD");

        requests = new Permissions[](10);
        requests[0] = Permissions(REWRD_KEYCODE, REWRD.emergencyWithdraw.selector);
        requests[1] = Permissions(REWRD_KEYCODE, REWRD.emergencyWithdrawAll.selector);
        requests[2] = Permissions(REWRD_KEYCODE, REWRD.enableDistributedToken.selector);
        requests[3] = Permissions(REWRD_KEYCODE, REWRD.disableDistributedToken.selector);
        requests[4] = Permissions(REWRD_KEYCODE, REWRD.updateCycleRewardsPercent.selector);
        requests[5] = Permissions(REWRD_KEYCODE, REWRD.removeTokenFromDistributedTokens.selector);
        requests[6] = Permissions(REWRD_KEYCODE, REWRD.addRewardsToPending.selector);
        requests[7] = Permissions(REWRD_KEYCODE, REWRD.updateAutoLockPercent.selector);
        requests[8] = Permissions(REWRD_KEYCODE, REWRD.harvestRewards.selector);
        requests[9] = Permissions(REWRD_KEYCODE, REWRD.harvestAllRewards.selector); 
    }

    function harvestRewards(address token) external {
        rewrd.harvestRewards(msg.sender, token);
    }

    function harvestAllRewards() external {
        rewrd.harvestAllRewards(msg.sender);
    }

    function emergencyWithdraw(ERC20 token) external OnlyOwner {
        rewrd.emergencyWithdraw(token, msg.sender);
    }

    function emergencyWithdrawAll() external OnlyOwner {
        rewrd.emergencyWithdrawAll(msg.sender);
    }

    function enableDistributedToken(address token) external OnlyOwner {
        rewrd.enableDistributedToken(token);
    }

    function addRewardsToPending(ERC20 token, uint256 amount) external OnlyOwner {
        rewrd.addRewardsToPending(token, msg.sender, amount);
    }


    function disableDistributedToken(address token) external OnlyOwner {
        rewrd.disableDistributedToken(token);
    }

    function updateCycleRewardsPercent(address token, uint256 percent) external OnlyOwner {
        rewrd.updateCycleRewardsPercent(token, percent);
    }

    function updateAutoLockPercent(address token, uint256 percent) external OnlyOwner {
        rewrd.updateAutoLockPercent(token, percent);
    }

    function removeTokenFromDistributedTokens(address tokenToRemove) external OnlyOwner {
        rewrd.removeTokenFromDistributedTokens(tokenToRemove);
    }
}
