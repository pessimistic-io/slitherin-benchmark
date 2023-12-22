//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "./BonesStakingState.sol";
import "./ContractControl.sol";
import "./ReentrancyGuardUpgradeable.sol";

contract BonesStaking is
    BonesStakingState,
    ContractControl,
    ReentrancyGuardUpgradeable
{
    function initialize() public initializer {
        ContractControl.initializeAccess();
        minStakeAmount = 1000 * 10 ** 18;
        reward = 100000000;
        boostPayment = 5000 * 10 ** 18;
        boostAmount = 1 * 10 ** 9;
        boostActive = false;
    }

    function setContracts(
        address _neanderSmols,
        address _bones,
        address _neanderStaking,
        address _treasury
    ) external onlyOwner {
        neanderSmols = IERC721Upgradeable(_neanderSmols);
        bones = _bones;
        neanderStaking = _neanderStaking;
        treasury = _treasury;
    }

    function stakeBones(
        uint256 _amount,
        uint256 _tokenId
    ) external contractsAreSet whenNotPaused {
        require(
            _amount % minStakeAmount == 0,
            "Can only stake multiples of minimum stake amount"
        );
        require(
            IBones(bones).balanceOf(msg.sender) >= _amount,
            "Not enough balance"
        );
        require(
            INeanderStaking(neanderStaking).getUserFromToken(_tokenId) ==
                msg.sender,
            "User is not staking tokenId"
        );
        userToStakeDetails[msg.sender].push(
            StakeDetails(_amount, block.timestamp, block.timestamp, _tokenId)
        );
        emit BonesStaked(msg.sender, _amount, block.timestamp);
        IBones(bones).transferFrom(msg.sender, address(this), _amount);
    }

    function unstakeBones(
        uint256 _startTime,
        uint256 _tokenId
    ) external contractsAreSet whenNotPaused nonReentrant {
        uint256 reward = getRewardAmount(_tokenId);
        if (reward > 0) {
            claimRewards(_tokenId);
        }
        uint256 amount = removeStake(_startTime, _tokenId);
        require(amount > 0, "Valid stake not provided");
        require(!isContract(msg.sender), "Bad ooga");
        IBones(bones).transfer(msg.sender, amount);
        emit BonesUnstaked(msg.sender, amount);
    }

    function removeStake(
        uint256 _startTime,
        uint256 _tokenId
    ) private returns (uint256) {
        StakeDetails[] storage details = userToStakeDetails[msg.sender];
        uint256 amount = 0;
        for (uint i = 0; i < details.length; i++) {
            if (
                details[i].startTime == _startTime &&
                details[i].tokenId == _tokenId
            ) {
                amount = details[i].amountStaked;
                details[i] = details[details.length - 1];
                details.pop();
                break;
            }
        }
        return amount;
    }

    function claimRewards(
        uint256 _tokenId
    ) public contractsAreSet whenNotPaused {
        StakeDetails[] storage current = userToStakeDetails[msg.sender];
        uint256 totalReward = 0;
        for (uint i = 0; i < current.length; i++) {
            if (current[i].tokenId == _tokenId) {
                totalReward += _getRewards(current[i]);
            }
        }
        require(totalReward > 0, "Not enough rewards to claim");
        INeanderSmol(address(neanderSmols)).updateCommonSense(
            _tokenId,
            totalReward
        );
        emit RewardClaimed(msg.sender, totalReward, _tokenId);
    }

    function _getRewards(
        StakeDetails storage current
    ) private returns (uint256) {
        uint256 lastRewardTime = current.lastRewardTime;
        uint256 rewardDays = (block.timestamp - lastRewardTime) / 1 days;
        if (rewardDays == 0) return 0;
        uint256 amount = current.amountStaked;
        uint256 rewardAmount = reward * rewardDays * (amount / minStakeAmount);
        uint256 newRewardStartTime = (rewardDays * 1 days) + lastRewardTime;
        current.lastRewardTime = newRewardStartTime;
        return rewardAmount;
    }

    function getRewardAmount(
        uint256 _tokenId
    ) public view contractsAreSet returns (uint256) {
        StakeDetails[] memory current = userToStakeDetails[msg.sender];
        uint256 totalReward = 0;
        for (uint i = 0; i < current.length; i++) {
            if (current[i].tokenId == _tokenId) {
                uint256 lastRewardTime = current[i].lastRewardTime;
                uint256 rewardDays = (block.timestamp - lastRewardTime) /
                    1 days;
                uint256 amount = current[i].amountStaked;
                uint256 rewardAmount = reward *
                    rewardDays *
                    (amount / minStakeAmount);
                totalReward += rewardAmount;
            }
        }
        return totalReward;
    }

    function unstakeAll() external {
        StakeDetails[] memory details = getStakes(msg.sender);
        uint256 length = details.length > 50 ? 50 : details.length;
        for (uint256 i; i < length; ++i) {
            uint256 tokenId = details[i].tokenId;
            uint256 reward = getRewardAmount(tokenId);
            if (reward > 0) {
                claimRewards(tokenId);
            }
            uint256 amount = removeStake(details[i].startTime, tokenId);
            require(amount > 0, "Valid stake not provided");
            require(!isContract(msg.sender), "Bad ooga");
            require(IBones(bones).transfer(msg.sender, amount), "Tx failed");
            emit BonesUnstaked(msg.sender, amount);
        }
    }

    function getStakes(
        address _user
    ) public view returns (StakeDetails[] memory) {
        return userToStakeDetails[_user];
    }

    function boostRewards(
        uint256 _amount,
        uint256 _tokenId
    ) external contractsAreSet whenBoostActive {
        require(
            IBones(bones).balanceOf(msg.sender) >= _amount,
            "Not enough balance"
        );
        require(_amount == boostPayment, "Wrong amount sent");
        IBones(bones).transferFrom(msg.sender, treasury, _amount);
        INeanderSmol(address(neanderSmols)).updateCommonSense(
            _tokenId,
            boostAmount
        );
        emit RewardBoosted(msg.sender, _tokenId);
    }

    function flipBoostState() external onlyAdmin {
        boostActive = !boostActive;
    }

    function setRewardAmount(uint256 _amount) external onlyAdmin {
        reward = _amount;
    }

    function setMinStakeAmount(uint256 _minStakeAmount) external onlyAdmin {
        minStakeAmount = _minStakeAmount;
    }

    function setReward(uint256 _reward) external onlyAdmin {
        reward = _reward;
    }

    function setBoostPaymentAndAmount(
        uint256 _payment,
        uint256 _amount
    ) external onlyAdmin {
        if (_payment != 0) {
            boostPayment = _payment;
        }
        if (_amount != 0) {
            boostAmount = _amount;
        }
    }

    function isContract(address addr) private view returns (bool) {
        uint size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}

