//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title PepeLockUpExtension contract.
 * @dev This contract is used to lock up Balancer PEG80-WETH20 lp tokens based on exiting lock information in PepeLockUp.sol.
 */
import { Ownable2Step } from "./Ownable2Step.sol";
import { PepeEsPegLPHelper } from "./PepeEsPegLPHelper.sol";
import { Lock, LockExtension } from "./Structs.sol";
import { IPepeProxyLpToken } from "./IPepeProxyLpToken.sol";
import { IPepeLockUp } from "./IPepeLockUp.sol";
import { IPepeLPTokenPool } from "./IPepeLPTokenPool.sol";

contract PepeLockUpExtension is Ownable2Step, PepeEsPegLPHelper {
    IPepeProxyLpToken public immutable pPlpToken;

    IPepeLockUp public pepeLockUp;
    IPepeLPTokenPool public pLpTokenPool;

    mapping(address user => LockExtension) public extensionLockDetails;

    event LockedProxyLp(address indexed user, uint256 amount);
    event UnlockedProxyLp(address indexed user, uint256 amount);
    event PepeLockUpUpdated(address indexed pepeLockUp);
    event LpTokenPoolUpdated(address indexed pLpTokenPool);
    event PepeLockUnlockFailed(address indexed user);

    constructor(address _pepeLockUp, address _pLpToken, address _pLpTokenPool) {
        pepeLockUp = IPepeLockUp(_pepeLockUp);
        pPlpToken = IPepeProxyLpToken(_pLpToken);
        pLpTokenPool = IPepeLPTokenPool(_pLpTokenPool);
    }

    function lockProxyLp(uint256 amount) external {
        require(amount != 0, "amount is 0");
        require(pPlpToken.transferFrom(msg.sender, address(this), amount), "pplp transfer failed");
        Lock memory userPepeLockDetails = pepeLockUp.getLockDetails(msg.sender);
        uint48 currentLockDuration = pepeLockUp.lockDuration();

        if (userPepeLockDetails.totalLpShare == 0) {
            //user unlocked all their lp tokens
            //lock up their current share for current lock duration
            _lock(msg.sender, amount, uint48(block.timestamp + currentLockDuration));
            return;
        }
        if (userPepeLockDetails.unlockTimestamp > block.timestamp) {
            //user has an existing lock
            _lock(msg.sender, amount, uint48(userPepeLockDetails.unlockTimestamp));
            return;
        }
        if (userPepeLockDetails.unlockTimestamp < block.timestamp) {
            //user has an existing lock but is available to unlock
            //do not lock lp tokens.
            _lock(msg.sender, amount, uint48(block.timestamp));
            return;
        }
    }

    function _lock(address _user, uint256 _amount, uint48 _lockTime) private {
        //transfer lp tokens from pool
        pLpTokenPool.fundContractOperation(address(this), _amount);

        LockExtension memory lockExtension = extensionLockDetails[_user];

        if (lockExtension.user == address(0)) {
            //user has no existing lock
            //create a new lock
            extensionLockDetails[_user] = LockExtension(_user, _amount, _lockTime);
            emit LockedProxyLp(_user, _amount);
        } else {
            //user has an existing lock
            //add to existing lock
            extensionLockDetails[_user].amount += _amount;
            emit LockedProxyLp(_user, _amount);
        }
    }

    function unLockLpPegWeth() external {
        LockExtension memory lockExtension = extensionLockDetails[msg.sender];
        require(lockExtension.lockDuration <= uint48(block.timestamp), "lock not expired");
        uint256 amount = lockExtension.amount;
        require(lockExtension.user != address(0), "no lock in lock extension");
        require(amount != 0, "no lock in lock extension");

        pPlpToken.burn(address(this), amount);

        //remove lock
        delete extensionLockDetails[msg.sender];

        _exitPool(amount);

        emit UnlockedProxyLp(msg.sender, amount);
    }

    function updatePepeLockUp(address _pepeLockUp) external onlyOwner {
        require(_pepeLockUp != address(0), "zero address");

        pepeLockUp = IPepeLockUp(_pepeLockUp);
        emit PepeLockUpUpdated(_pepeLockUp);
    }

    function updateLpTokenPool(address _pLpTokenPool) external onlyOwner {
        require(_pLpTokenPool != address(0), "zero address");

        pLpTokenPool = IPepeLPTokenPool(_pLpTokenPool);
        emit LpTokenPoolUpdated(_pLpTokenPool);
    }

    function getUserExtensionLockDetails(address user) external view returns (LockExtension memory) {
        return extensionLockDetails[user];
    }
}

