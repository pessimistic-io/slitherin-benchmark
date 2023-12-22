// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Ownable } from "./Ownable.sol";
import { IERC20Metadata } from "./interfaces_IERC20Metadata.sol";
import { SafeMath } from "./SafeMath.sol";
//import { SafeERC20 } from '../libraries/SafeERC20.sol';
import { SafeERC20 } from "./SafeERC20.sol";
import "./Staking.sol";
import "./TierController.sol";
import "./IRewardController.sol";


struct PhaseInfo {
    uint256 startBlock;
    uint256 endBlock;
    uint256 totalReward;
    uint256 claimedReward;
}


contract RewardController is Ownable, IRewardController {
    using SafeMath for uint256;

    // configuration
    IERC20Metadata immutable public token;
    TierController immutable public tierController;
    Staking immutable public staking;
    uint256 public phaseLength;
    uint256 public expiryLength;
    address public expiryRecipient;

    // phase state
    PhaseInfo[] public phases;
    PhaseInfo public currentPhase;
    // phase => user => claimed
    mapping(uint256 => mapping(address => uint256)) public userRewardClaimed;
    // phase => tier => count
    mapping(uint256 => uint32[]) public tierCounts;
    // phase => tier => amount
    mapping(uint256 => uint256[]) public tierAmounts;

    // tier count state
    uint256 public defaultTierCountSteps = 100;
    uint256 public phaseBeingUpdated = 0;
    uint256 public nextAddressIdx;
    mapping(address => uint256) public addressCountedAtPhase;
    bool public updateDone = true;


    constructor(IERC20Metadata _token, TierController _tierController, Staking _staking, uint256 _phaseLength, uint256 _expiryLength, address _expiryRecipient) {
        require(address(_token) != address(0), "Token address cannot be 0x0");
        token = _token;

        require(address(_tierController) != address(0), "TierController address cannot be 0x0");
        tierController = _tierController;

        require(address(_staking) != address(0), "Staking address cannot be 0x0");
        staking = _staking;

        setExpiryLength(_expiryLength);
        setPhaseLength(_phaseLength);
        setExpiryRecipient(_expiryRecipient);

        currentPhase.startBlock = block.number;
    }


    ///////////////////////////////////////
    // Core functionality
    ///////////////////////////////////////

    function tryClosePhase() public returns (uint256, bool) {
        bool updateTriggered = false;
        if (updateDone && block.number >= currentPhase.startBlock.add(phaseLength)) {
            currentPhase.endBlock = block.number;
            phases.push(currentPhase);
            updateTriggered = true;

            currentPhase = PhaseInfo(block.number, 0, 0, 0);

            tierController.snapshot();

            // reset tier counting
            phaseBeingUpdated = phases.length.sub(1);
            nextAddressIdx = 0;
            updateDone = false;
        }

        trySummarizeTierCounts();

        return (phaseBeingUpdated, !updateTriggered); // return the 'current phase', and true if all is done (no update triggered)
    }
    function trySummarizeTierCounts() public returns (bool) {
        return _trySummarizeTierCounts(defaultTierCountSteps);
    }
    function _trySummarizeTierCounts(uint256 _tierCountSteps) public returns (bool) {
        if (updateDone) {
            return true; // signal we are done
        }

        // what is the total subscription to each tier?
        uint256 _end = nextAddressIdx+_tierCountSteps;
        uint256 _addressCount = staking.getStakersCount();
        uint8 _tierCount = tierController.getTierCount();
        uint256 i;
        uint32[] memory _tierAdditions = new uint32[](tierController.getTierCount());
        for (i = nextAddressIdx;  i < _end && i < _addressCount;  ++i) {
            address account = staking.getStakers(i);

            // prevent double counting
            if (addressCountedAtPhase[account] == phaseBeingUpdated) {
                continue;
            }
            addressCountedAtPhase[account] = phaseBeingUpdated;

            // account for this user
            uint256 userTier = tierController.getTierIdx(phases[phases.length-1].endBlock, account);
            for (uint256 j = userTier;  j < _tierCount;  ++j) {
                require(_tierAdditions[j] < type(uint32).max, "Tier count overflow");
                _tierAdditions[j] += 1;
            }
        }

        // save results
        uint32[] storage _innerTierCount = tierCounts[phaseBeingUpdated];
        for (uint256 tier = 0;  tier < _tierAdditions.length;  ++tier) {
            if (_innerTierCount.length <= tier) {
                _innerTierCount.push(_tierAdditions[tier]);
            } else if (_tierAdditions[tier] > 0) {
                require(uint256(_innerTierCount[tier]).add(_tierAdditions[tier]) < type(uint32).max, "Tier count overflow 2");
                _innerTierCount[tier] += _tierAdditions[tier];
            }
        }
        nextAddressIdx = i;
        // did we finish?
        updateDone = i >= _addressCount;

        if (updateDone) {
            setTierAmounts();
        }

        return updateDone;
    }
    function setTierAmounts() internal {
        require(updateDone, "Cannot set tier amounts while updating");

        // calculate passforward per tier first
        uint256 _totalAmount = phases[phaseBeingUpdated].totalReward;
        uint256 passforwardAmountPerTier = 0;
        uint8 _tierCount = tierController.getTierCount();
        require(_tierCount > 0, "There has to be tiers");
        uint24 _FACTOR_DIVISOR = tierController.FACTOR_DIVISOR();
        uint24 _lastDexShareFactor = _FACTOR_DIVISOR;

        // calculate how much a user is owed based on their share of the tiers
        uint256 _passforwardAmount = 0;
        uint8 _lastPassforwardTier = 0;
        uint256[] storage _tierAmountsSub = tierAmounts[phaseBeingUpdated];
        require(_tierCount > 0, "There has to be tiers");
        while (_tierAmountsSub.length < _tierCount) {
            _tierAmountsSub.push(0);
        }

        for (uint8 _tier = 0;  _tier < uint256(_tierCount).sub(1);  ++_tier) {
            uint32 _usersAtTier = tierCounts[phaseBeingUpdated][_tier];

            uint24 _nextDexShareFactor;
            { // stack depth
                uint256 _discardedA;
                uint64 _discardedB;
                (_discardedA, _discardedB, _nextDexShareFactor) = tierController.rebateTiers(uint256(_tier).add(1));
            }
            uint256 _tierAmount = _totalAmount.mul(_lastDexShareFactor - _nextDexShareFactor).div(_FACTOR_DIVISOR);
            _lastDexShareFactor = _nextDexShareFactor;

            // if nobody is at this tier, then everyone below a share of that reward
            if (_usersAtTier == 0) {
                _passforwardAmount = _passforwardAmount.add(_tierAmount);
                _lastPassforwardTier = _tier;
                if (uint256(_lastPassforwardTier).add(2) != _tierCount) { // prevent div-by-zero
                    passforwardAmountPerTier = _passforwardAmount.div(uint256(_tierCount).sub(uint256(_lastPassforwardTier).add(2)));
                }
                
                // store result
                _tierAmountsSub[_tier] = 0;
            } else {
                // calculate and store the amount for this tier
                uint256  _tierAmountWithPassforward = _tierAmount.add(passforwardAmountPerTier);
                _tierAmountsSub[_tier] = _tierAmountWithPassforward.div(_usersAtTier);
            }
        }
    }
    function depositReward(uint256 amount) external {
        tryClosePhase();

        if (amount == 0) {
            return;
        }

        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);
        currentPhase.totalReward = currentPhase.totalReward.add(amount);
    }
    function claimRewards(bool _withdrawIfTrue) external returns (uint256) {
        tryClosePhase();

        // iterate backwards over all phases
        uint256 totalReward = 0;
        for (uint256 i = phases.length;  i > 0;  i--) {
            // if the phase has expired, end loop
            if (isPhaseExpired(i - 1)) {
                break;
            }

            totalReward += claimRewardForPhase(i - 1, _withdrawIfTrue);
        }

        return totalReward;
    }
    function claimRewardForPhase(uint256 _phaseIdx, bool _withdrawIfTrue) public returns (uint256) {
        PhaseInfo storage phase = phases[_phaseIdx];

        // how much is the user eligible for?
        uint256 userReward = getEligibleRewardForPhase(_phaseIdx, msg.sender);
        if (userReward == 0) {
            return 0; // early abort
        }

        mapping(address => uint256) storage _userRewardClaimed = userRewardClaimed[_phaseIdx];
        userReward = userReward.sub(_userRewardClaimed[msg.sender]);
        if (userReward == 0) {
            return 0;
        }
        if (userReward > phase.totalReward.sub(phase.claimedReward)) {
            // this should never happen, but just in case
            userReward = phase.totalReward.sub(phase.claimedReward);
        }


        // send the user their reward
        _userRewardClaimed[msg.sender] = _userRewardClaimed[msg.sender].add(userReward);
        phase.claimedReward = phase.claimedReward.add(userReward);
        require(phase.claimedReward <= phase.totalReward, "Claimed too much");
        // allow reinvest as default, withdraw as an option
        if (_withdrawIfTrue) {
            SafeERC20.safeTransfer(token, msg.sender, userReward);
        } else {
            IERC20(token).approve(address(staking), userReward);
            staking.stakeFor(msg.sender, userReward);
        }

        return userReward;
    }
    function getEligibleRewardForPhase(uint256 _phaseIdx, address _account) public view returns (uint256) {
        // only claim for phases we have the tiers for
        if (_phaseIdx > phaseBeingUpdated || (_phaseIdx == phaseBeingUpdated && !updateDone)) {
            return 0; // not yet finalized
        }

        // there's no reward if the phase is expired
        if (isPhaseExpired(_phaseIdx)) {
            return 0;
        }

        // calculate how much a user is owed based on their share of the tiers
        uint8 _userTier = tierController.getTierIdx(phases[_phaseIdx].endBlock, _account);
        uint8 _tierCount = tierController.getTierCount();
        uint256 _userAmount = 0;
        for (uint8 _tier = 0;  _tierCount > _tier;  ++_tier) {
            if (_tier < _userTier) {
                continue; // user isn't at this tier, skip further processing
            }

            // if the user is at this tier, then they get a share of that reward
            _userAmount = _userAmount.add(tierAmounts[_phaseIdx][_tier]);
        }

        return _userAmount.sub(userRewardClaimed[_phaseIdx][_account]);
    }
    function reclaimExpiredRewards() external returns (uint256) {
        require(expiryRecipient != address(0), "No expiry recipient set");

        // iterate over phases
        uint256 _result = 0;
        for (uint256 _phaseIdx = 0;  _phaseIdx < phases.length;  ++_phaseIdx) {
            if (!isPhaseExpired(_phaseIdx)) {
                continue;
            }

            PhaseInfo storage phase = phases[_phaseIdx];
            uint256 _amount = phase.totalReward.sub(phase.claimedReward);
            if (_amount > 0) {
                _result = _result.add(_amount);
                phase.claimedReward = phase.claimedReward.add(_amount);
                SafeERC20.safeTransfer(token, expiryRecipient, _amount);
            }
        }

        return _result;
    }


    ///////////////////////////////////////
    // View functions
    ///////////////////////////////////////

    function blocksUntilNextPhase() public view returns (uint256) {
        uint256 blocksSinceLastPhase = uint256(block.number).sub(getLastPhaseStart());
        if (blocksSinceLastPhase >= phaseLength) {
            return 0;
        } else {
            return phaseLength.sub(blocksSinceLastPhase);
        }
    }
    function getPastPhaseTotalReward() external view returns (uint256) {
        // get all rewards ever
        uint256 _result = 0;
        for (uint256 i = 0; i < phases.length; i++) {
            _result = _result.add(phases[i].totalReward);
        }
        return _result;
    }
    function getNextPhaseEstimatedReward() external view returns (uint256) {
        // get estimated total reward from next phase

        // is the phase done?
        if (getLastPhaseStart().add(phaseLength) <= block.number) {
            return currentPhase.totalReward;
        }

        if (block.number == getLastPhaseStart()) {
            return 0; // prevent divide by zero
        }

        // calculate the estimated reward
        return currentPhase.totalReward.mul(phaseLength).div(block.number.sub(getLastPhaseStart()));
    }
    function getClaimableRewardUser(address account) external view returns (uint256) {
        // get user available reward from finished phases
        uint256 _result = 0;
        for (uint256 _phaseIdx = 0;  _phaseIdx < phases.length;  ++_phaseIdx) {
            _result = _result.add(getEligibleRewardForPhase(_phaseIdx, account));
        }
        return _result;
    }
    function getPastPhaseTotalRewardUser(address account) external view returns (uint256) {
        // get all rewards ever for a specific address
        uint256 _result = 0;
        for (uint256 _phaseIdx = 0;  _phaseIdx < phases.length;  ++_phaseIdx) {
            _result = _result.add(userRewardClaimed[_phaseIdx][account]);
        }
        return _result;
    }
    function getPhaseCount() external view returns (uint256) {
        return phases.length;
    }
    function getLastPhaseStart() public view returns (uint256) {
        return currentPhase.startBlock;
    }


    ///////////////////////////////////////
    // Housekeeping
    ///////////////////////////////////////

    function changeOwner(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "New owner cannot be 0x0");

        transferOwnership(_newOwner);
    }
    function setPhaseLength(uint256 _phaseLength) public onlyOwner {
        require(_phaseLength > 0, "Phase length must be greater than 0");
        require(block.number > _phaseLength, 'Phase length too long');
        require(expiryLength > _phaseLength, 'Phase length longer than expiry length');
        phaseLength = _phaseLength;
    }
    function setExpiryLength(uint256 _expiryLength) public onlyOwner {
        require(block.number > _expiryLength, 'Expiry length too long');
        require(_expiryLength > phaseLength, 'Phase length longer than expiry length');
        expiryLength = _expiryLength;
    }
    function setExpiryRecipient(address _expiryRecipient) public onlyOwner {
        require(_expiryRecipient != address(0), "Expiry recipient cannot be 0x0");
        expiryRecipient = _expiryRecipient;
    }
    function setDefaultTierCountSteps(uint256 _defaultTierCountSteps) public onlyOwner {
        defaultTierCountSteps = _defaultTierCountSteps;
    }
    function isPhaseExpired(uint256 _phaseIdx) public view returns (bool) {
        return phases[_phaseIdx].endBlock.add(expiryLength) <= block.number;
    }
}

