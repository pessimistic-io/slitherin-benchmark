pragma solidity ^0.8.0;

import "./Kernel.sol";

import { ERC20 } from "./ERC20.sol";

// Module dependencies
import { REWRD } from "./REWRD.sol";
import { GMBL } from "./GMBL.sol";
import { REWRDV2 } from "./REWRDV2.sol";
import { XGMBLV2 } from "./XGMBLV2.sol";
import { ROLES } from "./ROLES.sol";
import { IxGMBLTokenUsage } from "./IxGMBLTokenUsage.sol";

contract RewardPolicyV2 is Policy {
    event PolicyAutoLockPercentUpdated(uint256 newPercent);

    error AutoLockPercentExceedsMax();

    REWRD public rewrd;
    REWRDV2 public rewrd2;
    ROLES public roles;
    GMBL public gmbl;
    XGMBLV2 public xgmbl2;

    uint256 public autoLockPercent;

    constructor(Kernel kernel_) Policy(kernel_) {}

    modifier OnlyOwner {
        roles.requireRole("rewardsmanager", msg.sender);
        _;
    }

    function configureDependencies() external override onlyKernel returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](5);
        dependencies[0] = toKeycode("REWRD");
        dependencies[1] = toKeycode("ROLES");
        dependencies[2] = toKeycode("RWRDB");
        dependencies[3] = toKeycode("GMBLE");
        dependencies[4] = toKeycode("XGBLB");

        rewrd = REWRD(getModuleAddress(dependencies[0]));
        roles = ROLES(getModuleAddress(dependencies[1]));
        rewrd2 = REWRDV2(getModuleAddress(dependencies[2]));
        gmbl = GMBL(getModuleAddress(dependencies[3]));
        xgmbl2 = XGMBLV2(getModuleAddress(dependencies[4]));
    }

    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        Keycode REWRD_KEYCODE = toKeycode("REWRD");
        Keycode REWRD2_KEYCODE = toKeycode("RWRDB");
        Keycode XGMBLV2_KEYCODE = toKeycode("XGBLB");

        requests = new Permissions[](22);
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

        requests[20] = Permissions(XGMBLV2_KEYCODE, XGMBLV2.convert.selector);
        requests[21] = Permissions(XGMBLV2_KEYCODE, XGMBLV2.allocate.selector);
    }

    function harvestRewards(address token) external {
        uint256 gmblBalanceBefore = gmbl.balanceOf(msg.sender);
        rewrd2.harvestRewards(msg.sender, token);
        uint256 gmblBalanceAfter = gmbl.balanceOf(msg.sender);

        uint256 relockAmount = (gmblBalanceAfter - gmblBalanceBefore) * autoLockPercent / 10000;

        xgmbl2.convert(relockAmount, relockAmount, msg.sender);
        xgmbl2.allocate(msg.sender, relockAmount, hex"00");
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

    function updateAutoLockPercentPolicy(uint256 _autoLockPercent) external OnlyOwner {
        if (_autoLockPercent > 10000) revert AutoLockPercentExceedsMax();
        autoLockPercent = _autoLockPercent;
        emit PolicyAutoLockPercentUpdated(_autoLockPercent);
    }

    function removeTokenFromDistributedTokens(address tokenToRemove) external OnlyOwner {
        rewrd2.removeTokenFromDistributedTokens(tokenToRemove);
    }
}
