// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./SignedSafeMath.sol";
import {Ownable} from "./Ownable.sol";

// ================================================================
// |██╗   ██╗███╗   ██╗███████╗██╗  ██╗███████╗████████╗██╗  ██╗
// |██║   ██║████╗  ██║██╔════╝██║  ██║██╔════╝╚══██╔══╝██║  ██║
// |██║   ██║██╔██╗ ██║███████╗███████║█████╗     ██║   ███████║
// |██║   ██║██║╚██╗██║╚════██║██╔══██║██╔══╝     ██║   ██╔══██║
// |╚██████╔╝██║ ╚████║███████║██║  ██║███████╗   ██║   ██║  ██║
// | ╚═════╝ ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝
// ================================================================
// ======================= GovernorsFarm =+++======================
// ================================================================
// Allows vdUSH users to enter the matrix and receive USH rewards
// Users can claim their rewards at any time
// No staking needed, just enter the matrix and claim rewards
// No user deposits held in this contract!
// ================================================================
// Arbitrum Farm also allows claiming of GRAIL / xGRAIL rewards
// ================================================================
// Author: unshETH team (github.com/unsheth)
// Heavily inspired by StakingRewards, MasterChef
//

interface IxGrail is IERC20 {
    function convertTo(uint amount, address to) external;
}

interface IvdUSH {
    function totalSupply() external view returns(uint);
    function balanceOf(address account) external view returns(uint);
    function deposit_for(address _addr, uint _valueA, uint _valueB, uint _valueC) external;
    function balanceOfAtT(address account, uint ts) external view returns(uint);
    function totalSupplyAtT(uint t) external view returns(uint);
    function user_point_epoch(address account) external view returns(uint);
    function user_point_history__ts(address _addr, uint _idx) external view returns (uint);
}

contract GovernorsFarm is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public constant USH = IERC20(0x51A80238B5738725128d3a3e06Ab41c1d4C05C74);
    IvdUSH public constant vdUsh = IvdUSH(0x69E3877a2A81345BAFD730e3E3dbEF74359988cA);
    IERC20 public constant GRAIL = IERC20(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    IxGrail public constant xGRAIL = IxGrail(0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b);
    
    uint public vdUshPercentage = 80e18; //percentage of rewards to lock as vdUSH
    uint public xGrailPercentage = 80e18; //percentage of GRAIL rewards to lock as xGRAIL

    //check if an address has entered the matrix
    mapping(address => bool) public isInMatrix;
    address[] public users; //array of users in the matrix

    uint public totalSupplyMultiplier = 1e18; //total supply multiplier to adjust for vdush total supply calc on bnb chain
    uint public ushPerSec;
    uint public grailPerSec;
    uint public startTime;

    mapping(address => uint) public lastClaimTimestamp;
    mapping(address => uint) public lastClaimVdUshBalance;
    mapping(address => uint) public lastClaimTotalSupply;
    mapping(address => bool) public isBlocked; //if a user is blocked from claiming rewards

    uint internal constant WEEK = 1 weeks;

    event MatrixEntered(address indexed _user);
    event RewardsClaimed(address indexed _user, uint _ushClaimed, uint _vdUSHClaimed, uint _grailClaimed, uint _xGrailClaimed);
    event RewardRateUpdated(uint _ushPerSec, uint _grailPerSec);
    event TotalSupplyMultiplierUpdated(uint _totalSupplyMultiplier);
    event LockPercentageUpdated(uint _vdUshLockPercentage, uint _xGrailLockPercentage);
    event BlockListUpdated(address indexed _user, bool _isBlocked);
    event FarmStarted(uint _ushPerSec, uint _grailPerSec, uint _startTime);

    //Constructor
    constructor() {
        USH.approve(address(vdUsh), type(uint).max); //for locking on behalf of users
        GRAIL.approve(address(xGRAIL), type(uint).max); //for locking on behalf of users
    }
    
    /**
     * @dev Allows a user with non zero vdUSH balance to enter the matrix and start earning farm rewards.
     * The user's address is registered in a mapping.
     * The user's last claim timestamp is set to the current block timestamp (rewards start from the moment they enter).
     * @param user The address of the user entering the matrix.
     */
    function enterMatrix(address user) external nonReentrant {
        _enterMatrix(user);
    }

    function _enterMatrix(address user) internal {
        require(!isInMatrix[user], "Already in matrix");
        require(vdUsh.balanceOf(user) > 0, "Cannot enter the matrix without vdUSH");
        isInMatrix[user] = true;
        users.push(user);
        lastClaimTimestamp[user] = block.timestamp;
        emit MatrixEntered(user);
    }

    /**
     * @dev Calculate user's earned USH and vdUSH rewards since last claim.
     * User earned rewards are proportional to their share of total vdUSH at the time of claim.
     * @param user The address of the user entering the matrix.
     */
    function earned(address user) public view returns (uint, uint, uint, uint) {
        require(isInMatrix[user], "User not in matrix");
        require(startTime!= 0 && block.timestamp > startTime, "Farm not started");
        require(!isBlocked[user], "User is blocked from claiming rewards");

        //calculate time from which to start accum rewards, max of (time user entered matrix, farm start time, last claim time)
        uint lastClaimTimeStamp = lastClaimTimestamp[user] > startTime ? lastClaimTimestamp[user] : startTime;

        uint secsSinceLastClaim = block.timestamp - lastClaimTimeStamp;
        uint lastEpoch = vdUsh.user_point_epoch(user);
        uint lastEpochTimestamp = vdUsh.user_point_history__ts(user, lastEpoch);

        uint userVdUsh;
        uint totalVdUsh;

        userVdUsh = lastClaimVdUshBalance[user];
        totalVdUsh = lastClaimTotalSupply[user];

        //sampling:
        //fyi we start at i=1, bc i=0 is the lastClaim which is already stored
        for(uint i = 1; i < 53;) {
            uint timestamp = lastClaimTimeStamp + i * 1 weeks;
            //if 1 wk after last claim is after current block timestamp, break
            if(timestamp > block.timestamp) {
                userVdUsh += vdUsh.balanceOf(user);
                totalVdUsh += vdUsh.totalSupply();
                break;
            }
            //round down to nearest week if needed
            if(timestamp > lastEpochTimestamp) {
                timestamp = lastEpochTimestamp;
            }

            userVdUsh += vdUsh.balanceOfAtT(user, timestamp);
            totalVdUsh += vdUsh.totalSupplyAtT(timestamp);

            unchecked{ ++i; }
        }

        uint averageVdUshShare = userVdUsh * 1e18 / totalVdUsh;

        uint totalWeight = averageVdUshShare * secsSinceLastClaim * totalSupplyMultiplier / 1e18;

        uint ushEarned = totalWeight * ushPerSec / 1e18;
        uint grailEarned = totalWeight * grailPerSec / 1e18;

        uint lockedUsh = ushEarned * vdUshPercentage / 100e18;
        uint claimableUsh = ushEarned - lockedUsh;

        uint lockedGrail = grailEarned * xGrailPercentage / 100e18;
        uint claimableGrail = grailEarned - lockedGrail;

        return (claimableUsh, lockedUsh, claimableGrail, lockedGrail);
    }

    /*
    ============================================================================
    Claim
    ============================================================================
    */

    function passGoAndCollect(address user) external nonReentrant {
        uint claimableUsh;
        uint lockedUsh;
        uint claimableGrail;
        uint lockedGrail;

        (claimableUsh, lockedUsh, claimableGrail, lockedGrail) = earned(user);

        require(lockedUsh > 0 || claimableUsh > 0 || claimableGrail > 0 || lockedGrail > 0, "Nothing to claim");

        lastClaimTimestamp[user] = block.timestamp;
        lastClaimVdUshBalance[user] = vdUsh.balanceOf(user);
        lastClaimTotalSupply[user] = vdUsh.totalSupply();

        //add to user's vdUSH if if nonzero
        if(lockedUsh > 0) {
            //add to user's vdUSH if their lock hasn't expired
            if(vdUsh.balanceOf(user) != 0) {
                vdUsh.deposit_for(user, 0, 0, lockedUsh);
            } else {
                lockedUsh = 0;
            }
        }

        //transfer claimable USH to user if nonzero
        if(claimableUsh > 0) {
            USH.safeTransfer(user, claimableUsh);
        }

        //add to user's xGrail if nonzero
        if(lockedGrail > 0) {
            xGRAIL.convertTo(lockedGrail, user);
        }

        //transfer claimable Grail to user if nonzero
        if(claimableGrail > 0) {
            GRAIL.safeTransfer(user, claimableGrail);
        }

        emit RewardsClaimed(user, claimableUsh, lockedUsh, claimableGrail, lockedGrail);
    }

    //view funcs
    function getAllUsers() public view returns (address[] memory) {
        return users;
    }

    function getVdUshTotalSupplyInFarm() public view returns (uint) {
        uint totalVdUsh;
        address[] memory _users = users;
        for(uint i = 0; i < _users.length;) {
            uint vdUshBalance = isBlocked[_users[i]] ? 0 : vdUsh.balanceOf(_users[i]);
            totalVdUsh += vdUshBalance;
            unchecked{ ++i; }
        }
        return totalVdUsh;
    }

    //owner funcs
    function startFarm(uint _ushPerSec, uint _grailPerSec) external onlyOwner {
        require(startTime == 0, "Farm already started");
        ushPerSec = _ushPerSec;
        grailPerSec = _grailPerSec;
        startTime = block.timestamp;
        emit FarmStarted(_ushPerSec, _grailPerSec, startTime);
    }

    function updateRewardRate(uint _ushPerSec, uint _grailPerSec) external onlyOwner {
        ushPerSec = _ushPerSec;
        grailPerSec = _grailPerSec;
        emit RewardRateUpdated(_ushPerSec, _grailPerSec);
    }

    function setLockPercentage(uint _vdUshPercentage, uint _xGrailPercentage) external onlyOwner {
        require(_vdUshPercentage <= 100e18, "vdUsh percentage too high");
        require(_xGrailPercentage <= 100e18, "xGrail percentage too high");
        vdUshPercentage = _vdUshPercentage;
        xGrailPercentage = _xGrailPercentage;
        emit LockPercentageUpdated(_vdUshPercentage, _xGrailPercentage);
    }

    function setTotalSupplyMultiplier(uint _totalSupplyMultiplier) external onlyOwner {
        totalSupplyMultiplier = _totalSupplyMultiplier; //make sure to set it in 1e18 terms
        emit TotalSupplyMultiplierUpdated(_totalSupplyMultiplier);
    }

    function setTotalSupplyMultiplier_onChain() external onlyOwner {
        totalSupplyMultiplier = vdUsh.totalSupply() * 1e18 / getVdUshTotalSupplyInFarm();
        emit TotalSupplyMultiplierUpdated(totalSupplyMultiplier);
    }

    function updateBlockList(address _user, bool _isBlocked) external onlyOwner {
        isBlocked[_user] = _isBlocked;
        emit BlockListUpdated(_user, _isBlocked);
    }

    //emergency funcs
    function recoverTokens(address token, uint amount, address dst) external onlyOwner {
        require(dst != address(0), "Cannot recover tokens to the zero address");
        IERC20(token).safeTransfer(dst, amount);
    }
}
