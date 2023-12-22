//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC1155BurnableUpgradeable.sol";

import "./ISmolFarm.sol";
import "./SmolFarmContracts.sol";

contract SmolFarm is Initializable, ISmolFarm, SmolFarmContracts {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        SmolFarmContracts.__SmolFarmContracts_init();
    }

    function setRewards(
        uint256[] calldata _rewardIds,
        uint32[] calldata _rewardOdds)
    external
    onlyAdminOrOwner
    nonZeroLength(_rewardIds)
    {
        require(_rewardIds.length == _rewardOdds.length, "Bad lengths");

        delete rewardOptions;

        uint32 _totalOdds;
        for(uint256 i = 0; i < _rewardIds.length; i++) {
            _totalOdds += _rewardOdds[i];

            rewardOptions.push(_rewardIds[i]);
            rewardIdToOdds[_rewardIds[i]] = _rewardOdds[i];
        }

        require(_totalOdds == 100000, "Bad total odds");
    }

    function stakeSmol(
        uint256[] calldata _brainsTokens,
        uint256[] calldata _bodiesTokens)
    external
    onlyEOA
    contractsAreSet
    whenNotPaused
    {
        require(_brainsTokens.length > 0 || _bodiesTokens.length > 0, "no tokens given");
        for(uint256 i = 0; i < _brainsTokens.length; i++) {
            _stakeSmol(smolBrains, _brainsTokens[i]);
        }
        for(uint256 i = 0; i < _bodiesTokens.length; i++) {
            _stakeSmol(smolBodies, _bodiesTokens[i]);
        }
    }

    function _stakeSmol(IERC721 smol, uint256 _tokenId) private {
        userToTokensStaked[address(smol)][msg.sender].add(_tokenId);

        tokenIdToStakeStartTime[address(smol)][_tokenId] = block.timestamp;

        emit SmolStaked(msg.sender, address(smol), _tokenId, block.timestamp);

        // will revert if user does not own token
        smol.safeTransferFrom(msg.sender, address(this), _tokenId);
    }

    function unstakeSmol(
        uint256[] calldata _brainsTokens,
        uint256[] calldata _bodiesTokens)
    external
    onlyEOA
    contractsAreSet
    whenNotPaused
    {
        require(_brainsTokens.length > 0 || _bodiesTokens.length > 0, "no tokens given");
        for(uint256 i = 0; i < _brainsTokens.length; i++) {
            _unstakeSmol(smolBrains, _brainsTokens[i]);
        }
        for(uint256 i = 0; i < _bodiesTokens.length; i++) {
            _unstakeSmol(smolBodies, _bodiesTokens[i]);
        }
    }

    function _unstakeSmol(IERC721 smol, uint256 _tokenId) private {
        require(userToTokensStaked[address(smol)][msg.sender].contains(_tokenId), "Not owned by user");
        require(tokenIdToRequestId[address(smol)][_tokenId] == 0, "Claim in progress");
        require(numberOfRewardsToClaim(address(smol), _tokenId) == 0, "Rewards left unclaimed!");

        userToTokensStaked[address(smol)][msg.sender].remove(_tokenId);

        delete tokenIdToStakeStartTime[address(smol)][_tokenId];
        delete tokenIdToRewardsClaimed[address(smol)][_tokenId];

        emit SmolUnstaked(msg.sender, address(smol), _tokenId);

        smol.safeTransferFrom(address(this), msg.sender, _tokenId);
    }

    function startClaimingRewards(
        uint256[] calldata _brainsTokens,
        uint256[] calldata _bodiesTokens)
    external
    onlyEOA
    contractsAreSet
    whenNotPaused
    {
        require(_brainsTokens.length > 0 || _bodiesTokens.length > 0, "no tokens given");
        for(uint256 i = 0; i < _brainsTokens.length; i++) {
           _startClaimingReward(smolBrains, _brainsTokens[i]);
        }
        for(uint256 i = 0; i < _bodiesTokens.length; i++) {
           _startClaimingReward(smolBodies, _bodiesTokens[i]);
        }
    }

    function _startClaimingReward(IERC721 smol, uint256 _tokenId) private {
        require(userToTokensStaked[address(smol)][msg.sender].contains(_tokenId), "Not owned by user");
        require(tokenIdToRequestId[address(smol)][_tokenId] == 0, "Claim in progress");

        uint256 _numberToClaim = numberOfRewardsToClaim(address(smol), _tokenId);
        require(_numberToClaim > 0, "No rewards to claim");

        tokenIdToRewardsClaimed[address(smol)][_tokenId] += _numberToClaim;
        tokenIdToRewardsInProgress[address(smol)][_tokenId] = _numberToClaim;

        uint256 _requestId = randomizer.requestRandomNumber();
        tokenIdToRequestId[address(smol)][_tokenId] = _requestId;

        emit StartClaiming(msg.sender, address(smol), _tokenId, _requestId, _numberToClaim);
    }

    function finishClaimingRewards(
        uint256[] calldata _brainsTokens,
        uint256[] calldata _bodiesTokens)
    external
    onlyEOA
    contractsAreSet
    whenNotPaused
    {
        require(_brainsTokens.length > 0 || _bodiesTokens.length > 0, "no tokens given");
        for(uint256 i = 0; i < _brainsTokens.length; i++) {
           _finishClaimingReward(smolBrains, _brainsTokens[i]);
        }
        for(uint256 i = 0; i < _bodiesTokens.length; i++) {
           _finishClaimingReward(smolBodies, _bodiesTokens[i]);
        }
    }

    function _finishClaimingReward(IERC721 smol, uint256 _tokenId) private {
        require(userToTokensStaked[address(smol)][msg.sender].contains(_tokenId), "Not owned by user");
        require(rewardOptions.length > 0, "Rewards not setup");

        uint256 _requestId = tokenIdToRequestId[address(smol)][_tokenId];
        require(_requestId != 0, "No claim in progress");

        require(randomizer.isRandomReady(_requestId), "Random not ready");

        uint256 _randomNumber = randomizer.revealRandomNumber(_requestId);

        uint256 _numberToClaim = tokenIdToRewardsInProgress[address(smol)][_tokenId];

        for(uint256 i = 0; i < _numberToClaim; i++) {
            if(i != 0) {
                _randomNumber = uint256(keccak256(abi.encode(_randomNumber, i)));
            }

            _claimReward(smol, _tokenId, _randomNumber);
        }

        delete tokenIdToRewardsInProgress[address(smol)][_tokenId];
        delete tokenIdToRequestId[address(smol)][_tokenId];
    }

    function _claimReward(IERC721 smol, uint256 _tokenId, uint256 _randomNumber) private {
        uint256 _rewardResult = _randomNumber % 100000;

        uint256 _topRange = 0;
        uint256 _claimedRewardId = 0;
        for(uint256 i = 0; i < rewardOptions.length; i++) {
            uint256 _rewardId = rewardOptions[i];
            _topRange += rewardIdToOdds[_rewardId];
            if(_rewardResult < _topRange) {
                _claimedRewardId = _rewardId;

                treasures.mint(msg.sender, _claimedRewardId, 1);

                break;
            }
        }

        emit RewardClaimed(msg.sender, address(smol), _tokenId, _claimedRewardId, 1);
    }

    function numberOfRewardsToClaim(address smolAddress, uint256 _tokenId) public view returns(uint256) {
        if(tokenIdToStakeStartTime[smolAddress][_tokenId] == 0 
            || tokenIdToStakeStartTime[smolAddress][_tokenId] >= _endEmissionTime)
        {
            return 0;
        }

        uint256 _timeForCalculation = tokenIdToStakeStartTime[smolAddress][_tokenId] + (tokenIdToRewardsClaimed[smolAddress][_tokenId] * _timeForReward);
        uint256 rewardTime = block.timestamp;

        // End of farm emissions has passed, no longer provide emissions after that end time.
        if(_endEmissionTime > 0 && _endEmissionTime < block.timestamp) {
            rewardTime = _endEmissionTime;
        }

        return (rewardTime - _timeForCalculation) / _timeForReward;
    }

    function setTimeForReward(uint256 _rewardTime) external onlyAdminOrOwner {
        _timeForReward = _rewardTime;
    }

    function setEndTimeForEmissions(uint256 _endTime) external onlyAdminOrOwner {
        _endEmissionTime = _endTime;
    }

    function ownsToken(address _collection, address _owner, uint256 _tokenId) external view returns (bool) {
        return userToTokensStaked[_collection][_owner].contains(_tokenId);
    }

    function tokensOfOwner(address _collection, address _owner) external view returns (uint256[] memory) { 
        return userToTokensStaked[_collection][_owner].values();
    }

}
