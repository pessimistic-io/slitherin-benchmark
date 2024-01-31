// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721A.sol";
import "./ERC721Holder.sol";
import "./ERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./console.sol";

contract NFTStaker is ERC721Holder, ReentrancyGuard, Ownable {
    ERC721A public parentNFT;
    ERC20 public rewardsToken;

    // Staker must be structured this way because of the important function getStakedTokens() below that returns the tokenIds array directly.
    struct Staker { 
        uint256[] tokenIds;
        uint256[] timestamps;
        Mission[] missions;
        uint256 tokensToClaim;
        bool[] tokensReceived;
    }

    struct Mission {
        uint256 startTimestamp;
        uint256 duration; // In hours
    }

    uint256 public hoursForUnitReward; // Hours needed to be rewarded one unit of token
    Mission currentMission;
    mapping(address => Staker) private stakers;
    
    event StakeSuccessful(
        uint256 tokenId,
        uint256 timestamp
    );
    
    event UnstakeSuccessful(
        uint256 tokenId,
        uint256 reward
    );

    constructor(address nftAddress) {
        parentNFT = ERC721A(nftAddress);
        hoursForUnitReward = 4; // 1 unit rewarded every 4 hours
    }

    function setOwnerAndTokenAddress(address _newOwner, address _tokenAddress) external onlyOwner {
        rewardsToken = ERC20(_tokenAddress);
        _transferOwnership(_newOwner);
    }

    function startMission(uint256 _duration) external onlyOwner {
        currentMission.startTimestamp = block.timestamp;
        currentMission.duration = _duration * 3600; // hours to seconds
    }

    function isMissionOngoing() view public returns(bool) {
        return currentMission.startTimestamp > 0 && (block.timestamp - currentMission.startTimestamp < currentMission.duration);
    }

    function stake(uint256 _tokenId) public nonReentrant {
        require(isMissionOngoing(), "There is no ongoing mission!");
        stakers[msg.sender].tokenIds.push(_tokenId);
        stakers[msg.sender].timestamps.push(block.timestamp);
        stakers[msg.sender].missions.push(currentMission);
        stakers[msg.sender].tokensReceived.push(false);
        parentNFT.safeTransferFrom(msg.sender, address(this), _tokenId);

        emit StakeSuccessful(_tokenId, block.timestamp);
    }

    function findIndexForTokenStaker(uint256 _tokenId, address _stakerAddress) private view returns(uint256, bool) {
        Staker memory _staker = stakers[_stakerAddress];

        uint256 _tokenIndex = 0;
        bool _foundIndex = false;
        
        uint256 _tokensLength = _staker.tokenIds.length;
        for(uint256 i = 0; i < _tokensLength; i ++) {
            if (_staker.tokenIds[i] == _tokenId) {
                _tokenIndex = i;
                _foundIndex = true;
                break;
            }
        }

        return (_tokenIndex, _foundIndex);
    }

    function getRewardForTokenIndexStaker(uint256 _tokenIndex, address _stakerAddress) private view returns(uint256) {
        Staker memory _staker = stakers[_stakerAddress];

        // If the player unstakes later than the end of the mission, don't count the time after that
        uint256 _missionEndTimestamp = _staker.missions[_tokenIndex].startTimestamp + _staker.missions[_tokenIndex].duration;
        uint256 _leaveMissionTimestamp = block.timestamp > _missionEndTimestamp ? _missionEndTimestamp : block.timestamp;
        // Handout reward depending on the stakingTime
        uint256 _stakingTime = _leaveMissionTimestamp - _staker.timestamps[_tokenIndex];

        uint256 _hoursPassed = _stakingTime / 3600;
        uint256 _reward = _hoursPassed / hoursForUnitReward;

        return _reward;
    }

    function unstake(uint256 _tokenId) public nonReentrant {
        Staker memory _staker = stakers[msg.sender];
        (uint256 _tokenIndex, bool _foundIndex) = findIndexForTokenStaker(_tokenId, msg.sender);
        require(_foundIndex, "Index not found for this staker.");

        uint256 _reward = getRewardForTokenIndexStaker(_tokenIndex, msg.sender);

        bool _missionIsOver = isSpecificMissionOver(_staker.missions[_tokenIndex].startTimestamp, 
                                                    _staker.missions[_tokenIndex].duration, 
                                                    block.timestamp);

        // Unstake NFT from this smart contract
        parentNFT.safeTransferFrom(address(this), msg.sender, _tokenId);

        // Only reward if the mission is over
        if (_missionIsOver && _staker.tokensReceived[_tokenIndex] == false) {
            stakers[msg.sender].tokensReceived[_tokenIndex] = true;
            stakers[msg.sender].tokensToClaim += _reward;
        }
        
        removeStakerElement(_tokenIndex, _staker.tokenIds.length - 1);

        emit UnstakeSuccessful(_tokenId, _reward);
    }

    function sendAllInactiveToMission(uint256[] memory _tokenIds) public nonReentrant {
        require(isMissionOngoing(), "There is no ongoing mission!");
        
        uint256 _tokensIdsLength = _tokenIds.length;
        uint256 _currentTimestamp = block.timestamp;
        for (uint256 i = 0; i < _tokensIdsLength;) {
            
            (uint256 _tokenIndex, bool _foundIndex) = findIndexForTokenStaker(_tokenIds[i], msg.sender);
            require(_foundIndex, "Index not found for this staker.");
            require(isSpecificMissionOver(stakers[msg.sender].missions[_tokenIndex].startTimestamp, stakers[msg.sender].missions[_tokenIndex].duration, _currentTimestamp), 
                "This Gelato is still on an ongoing mission!");
            
            uint256 _reward = getRewardForTokenIndexStaker(_tokenIndex, msg.sender);
            
            // Add reward from last mission
            if (stakers[msg.sender].tokensReceived[_tokenIndex] == false) {
                stakers[msg.sender].tokensToClaim += _reward;
            }
            
            // Send to next mission
            stakers[msg.sender].timestamps[_tokenIndex] = _currentTimestamp;
            stakers[msg.sender].missions[_tokenIndex] = currentMission;
            stakers[msg.sender].tokensReceived[_tokenIndex] = false;

            unchecked { ++i; }
        }
    }

    function isSpecificMissionOver(uint256 _timestamp, uint256 _duration, uint256 _currentTimestamp) internal pure returns(bool) {
        return _timestamp + _duration < _currentTimestamp;
    }

    function claimReward() external {
        uint256 _reward = getRewardToClaim(msg.sender);
        require(_reward > 0, "No tokens to claim.");

        if (rewardsToken.transfer(msg.sender, _reward) == true) {
            uint256 _stakedTokensLength = getStakedTokens(msg.sender).length;
            uint256 _currentTimestamp = block.timestamp;
            for (uint256 i = 0; i < _stakedTokensLength;) {
                bool _isMissionOver = isSpecificMissionOver(stakers[msg.sender].missions[i].startTimestamp, stakers[msg.sender].missions[i].duration, _currentTimestamp);
                if (_isMissionOver) { // Don't mark as claimed if the next mission has already been started
                    stakers[msg.sender].tokensReceived[i] = true;
                }
                unchecked { ++i; }
            }
            stakers[msg.sender].tokensToClaim = 0;
        }
        else revert();
    }

    function removeStakerElement(uint256 _tokenIndex, uint256 _lastIndex) internal {
        stakers[msg.sender].timestamps[_tokenIndex] = stakers[msg.sender].timestamps[_lastIndex];
        stakers[msg.sender].timestamps.pop();

        stakers[msg.sender].tokenIds[_tokenIndex] = stakers[msg.sender].tokenIds[_lastIndex];
        stakers[msg.sender].tokenIds.pop();

        stakers[msg.sender].missions[_tokenIndex] = stakers[msg.sender].missions[_lastIndex];
        stakers[msg.sender].missions.pop();

        stakers[msg.sender].tokensReceived[_tokenIndex] = stakers[msg.sender].tokensReceived[_lastIndex];
        stakers[msg.sender].tokensReceived.pop();
    }

    function isTokenStaked(uint256 _tokenId) public view returns(bool) {
        uint256 _tokensLength = stakers[msg.sender].tokenIds.length;
        for(uint256 i = 0; i < _tokensLength; i ++) {
            if (stakers[msg.sender].tokenIds[i] == _tokenId) {
                return true;
            }
        }
        return false;
    }
    
    function getStakedTokens(address _user) public view returns (uint256[] memory tokenIds) {
        return stakers[_user].tokenIds;
    }
    
    function getStakedTimestamps(address _user) public view returns (uint256[] memory timestamps) {
        return stakers[_user].timestamps;
    }
    
    function getStakedMissions(address _user) public view returns (Mission[] memory missions) {
        return stakers[_user].missions;
    }

    // Frontend purposes only
    function getRewardFromActiveMission(address _user) external view returns (uint256) {
        Staker memory _staker = stakers[_user];
        uint256 _rewardFromActiveMission = 0;
        uint256 _stakedTokensLength = getStakedTokens(_user).length;

        for (uint256 i = 0; i < _stakedTokensLength;) {
            if (!_staker.tokensReceived[i]) {
                _rewardFromActiveMission += (_staker.missions[i].duration / 3600) / hoursForUnitReward;
            }
            unchecked { ++i; }
        }

        return _rewardFromActiveMission;
    }
    
    function getRewardToClaim(address _user) public view returns (uint256) {
        uint256 _tokensToClaim = stakers[_user].tokensToClaim;

        // Find out if some gelatos' missions are over and tokens were not received for them yet
        uint256 _stakedTokensLength = getStakedTokens(_user).length;

        uint256 _currentTimestamp = block.timestamp;
        for (uint256 i = 0; i < _stakedTokensLength;) {
            if (!stakers[_user].tokensReceived[i] && isSpecificMissionOver(stakers[_user].missions[i].startTimestamp, stakers[_user].missions[i].duration, _currentTimestamp)) {
                _tokensToClaim += getRewardForTokenIndexStaker(i, _user);
            }
            unchecked { ++i; }
        }

        return _tokensToClaim;
    }

    function setHoursForUnitReward(uint256 _hoursForUnitReward) public onlyOwner {
        require(_hoursForUnitReward > 0, "Can't set to 0");
        hoursForUnitReward = _hoursForUnitReward;
    }
}
