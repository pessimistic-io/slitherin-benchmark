pragma solidity ^0.8.0;

import "./Kernel.sol";

import { ERC20 } from "./ERC20.sol";

// Module dependencies
import { REWRD } from "./REWRD.sol";
import { REWRDV2 } from "./REWRDV2.sol";
import { ROLES } from "./ROLES.sol";
import { IxGMBLTokenUsage } from "./IxGMBLTokenUsage.sol";

contract RewardPolicyV2 is Policy {
    REWRD public rewrd;
    REWRDV2 public rewrd2;
    ROLES public roles;

    constructor(Kernel kernel_) Policy(kernel_) {}

    modifier OnlyOwner {
        roles.requireRole("rewardsmanager", msg.sender);
        _;
    }

    function configureDependencies() external override onlyKernel returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("REWRD");
        dependencies[1] = toKeycode("ROLES");
        dependencies[2] = toKeycode("RWRDB");

        rewrd = REWRD(getModuleAddress(dependencies[0]));
        roles = ROLES(getModuleAddress(dependencies[1]));
        rewrd2 = REWRDV2(getModuleAddress(dependencies[2]));
    }

    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        Keycode REWRD_KEYCODE = toKeycode("REWRD");
        Keycode REWRD2_KEYCODE = toKeycode("RWRDB");

        requests = new Permissions[](20);
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

        requests[10] = Permissions(REWRD2_KEYCODE, REWRDV2.emergencyWithdraw.selector);
        requests[11] = Permissions(REWRD2_KEYCODE, REWRDV2.emergencyWithdrawAll.selector);
        requests[12] = Permissions(REWRD2_KEYCODE, REWRDV2.enableDistributedToken.selector);
        requests[13] = Permissions(REWRD2_KEYCODE, REWRDV2.disableDistributedToken.selector);
        requests[14] = Permissions(REWRD2_KEYCODE, REWRDV2.updateCycleRewardsPercent.selector);
        requests[15] = Permissions(REWRD2_KEYCODE, REWRDV2.removeTokenFromDistributedTokens.selector);
        requests[16] = Permissions(REWRD2_KEYCODE, REWRDV2.addRewardsToPending.selector);
        requests[17] = Permissions(REWRD2_KEYCODE, REWRDV2.updateAutoLockPercent.selector);
        requests[18] = Permissions(REWRD2_KEYCODE, REWRDV2.harvestRewards.selector);
        requests[19] = Permissions(REWRD2_KEYCODE, REWRDV2.harvestAllRewards.selector);
    }

    function harvestRewards(address token) external {
        rewrd2.harvestRewards(msg.sender, token);
    }

    function harvestAllRewards() external {
        rewrd2.harvestAllRewards(msg.sender);
    }

    function emergencyWithdraw(ERC20 token) external OnlyOwner {
        rewrd2.emergencyWithdraw(token, msg.sender);
    }

    function emergencyWithdrawAll() external OnlyOwner {
        rewrd2.emergencyWithdrawAll(msg.sender);
    }

    function enableDistributedToken(address token) external OnlyOwner {
        rewrd2.enableDistributedToken(token);
    }

    function addRewardsToPending(ERC20 token, uint256 amount) external OnlyOwner {
        rewrd2.addRewardsToPending(token, msg.sender, amount);
    }

    function disableDistributedToken(address token) external OnlyOwner {
        rewrd2.disableDistributedToken(token);
    }

    function updateCycleRewardsPercent(address token, uint256 percent) external OnlyOwner {
        rewrd2.updateCycleRewardsPercent(token, percent);
    }

    function updateAutoLockPercent(address token, uint256 percent) external OnlyOwner {
        rewrd2.updateAutoLockPercent(token, percent);
    }

    function removeTokenFromDistributedTokens(address tokenToRemove) external OnlyOwner {
        rewrd2.removeTokenFromDistributedTokens(tokenToRemove);
    }
}
