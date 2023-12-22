// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721Enumerable.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

import "./IRubicStaking.sol";
import "./IERC20Minimal.sol";

import "./TransferHelper.sol";
import "./FullMath.sol";

contract RubicStaking is IRubicStaking, ERC721Enumerable, ReentrancyGuard, Ownable {
    struct Stake {
        uint128 lockTime;
        uint128 lockStartTime;
        uint256 amount;
        uint256 lastRewardGrowth;
    }

    IERC20Minimal public immutable RBC;
    uint256 constant PRECISION = 10**29;

    mapping(uint256 => Stake) public stakes;
    uint256 public rewardRate;
    uint256 public rewardReserve;
    uint128 public prevTimestamp;

    uint256 public virtualRBCBalance;
    uint256 public rewardGrowth = 1;
    bool public emergencyStop;

    uint256 private _tokenId = 1;

    constructor(address _RBC) ERC721('Rubic Staking NFT', 'RBC-STAKE') {
        RBC = IERC20Minimal(_RBC);
        prevTimestamp = uint128(block.timestamp);
    }

    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), 'Not authorized');
        _;
    }

    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(owner);
        uint256[] memory ownedTokens = new uint256[](balance);

        for (uint256 i; i < balance; i++) {
            ownedTokens[i] = tokenOfOwnerByIndex(owner, i);
        }

        return ownedTokens;
    }

    function estimatedAnnualRewardsByTokenId(uint256 tokenId) external view returns (uint256) {
        uint256 estimatedReward = rewardRate * 365 * 24 * 60 * 60;
        uint256 estimatedRewardGrowth = rewardGrowth + FullMath.mulDiv(estimatedReward, PRECISION, virtualRBCBalance);

        Stake memory stake = stakes[tokenId];
        uint256 rewards = FullMath.mulDiv(
            getAmountWithMultiplier(stake.amount, stake.lockTime),
            estimatedRewardGrowth - stake.lastRewardGrowth,
            PRECISION
        );

        return rewards;
    }

    function setRate(uint256 rate) external override onlyOwner {
        require(rate < 10**27, 'too high rate');
        _increaseCumulative(uint128(block.timestamp));
        rewardRate = rate;
        emit Rate(rate);
    }

    function setEmergencyStop(bool _emergencyStop) external override onlyOwner {
        emergencyStop = _emergencyStop;
        emit EmergencyStop(_emergencyStop);
    }

    function addRewards() external payable override {
        _increaseCumulative(uint128(block.timestamp));
        if (msg.value > 0) {
            rewardReserve += msg.value;
            emit AddRewards(msg.value);
        }
    }

    function enterStaking(uint256 _amount, uint128 _lockTime) external override {
        require(_amount > 0, 'stake amount should be correct');
        require(!emergencyStop, 'staking is stopped');

        TransferHelper.safeTransferFrom(address(RBC), msg.sender, address(this), _amount);
        uint256 tokenId = _stake(_amount, _lockTime, msg.sender);
        emit Enter(_amount, _lockTime, tokenId);
    }

    function enterStakingTo(uint256 _amount, uint128 _lockTime, address _to) external override {
        require(_amount > 0, 'stake amount should be correct');
        require(_to != address(0), 'to is zero');
        require(!emergencyStop, 'staking is stopped');

        TransferHelper.safeTransferFrom(address(RBC), msg.sender, address(this), _amount);
        uint256 tokenId = _stake(_amount, _lockTime, _to);
        emit Enter(_amount, _lockTime, tokenId);
    }

    function unstake(uint256 tokenId) external override nonReentrant isAuthorizedForToken(tokenId) {
        _increaseCumulative(uint128(block.timestamp));
        Stake memory stake = stakes[tokenId];

        require(stake.lockStartTime + stake.lockTime < block.timestamp || emergencyStop, 'lock isnt expired');

        uint256 amountWithMultiplier = getAmountWithMultiplier(stake.amount, stake.lockTime);
        uint256 rewards = FullMath.mulDiv(amountWithMultiplier, rewardGrowth - stake.lastRewardGrowth, PRECISION);

        virtualRBCBalance -= amountWithMultiplier;

        TransferHelper.safeTransfer(address(RBC), msg.sender, stake.amount);

        (bool success, ) = msg.sender.call{value: rewards}('');
        require(success, 'rewards transfer failed');

        _burn(tokenId);
        delete stakes[tokenId];
        emit Unstake(stake.amount, tokenId);
    }

    function claimRewards(uint256 tokenId) external override nonReentrant isAuthorizedForToken(tokenId) returns (uint256 rewards) {
        _increaseCumulative(uint128(block.timestamp));
        Stake storage stake = stakes[tokenId];

        require(stake.amount > 0, 'amount should be correct');

        rewards = FullMath.mulDiv(
            getAmountWithMultiplier(stake.amount, stake.lockTime),
            rewardGrowth - stake.lastRewardGrowth,
            PRECISION
        );
        stake.lastRewardGrowth = rewardGrowth;

        (bool success, ) = msg.sender.call{value: rewards}('');
        require(success, 'rewards transfer failed');

        emit Claim(rewards, tokenId);
    }

    function calculateRewards(uint256 tokenId) external view override returns (uint256 rewards) {
        uint256 _rewardRate = rewardRate;
        uint256 _rewardGrowth = rewardGrowth;
        uint256 _rewardReserve = _rewardRate > 0 ? rewardReserve : 0;
        if (_rewardReserve > 0) {
            uint256 reward = _rewardRate * (block.timestamp - prevTimestamp);
            if (reward > _rewardReserve) reward = _rewardReserve;
            _rewardGrowth += FullMath.mulDiv(reward, PRECISION, virtualRBCBalance);
        }
        Stake memory stake = stakes[tokenId];
        rewards = FullMath.mulDiv(
            getAmountWithMultiplier(stake.amount, stake.lockTime),
            _rewardGrowth - stake.lastRewardGrowth,
            PRECISION
        );
    }

    function sweepTokens(
        address _asset,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        require(_asset != address(RBC), 'cannot sweep RBC');

        address sendTo = _to == address(0) ? msg.sender : _to;
        if (_asset == address(0)) {
            _increaseCumulative(uint128(block.timestamp));

            rewardReserve -= _amount;

            (bool success, ) = sendTo.call{value: _amount}('');
            require(success, 'rewards transfer failed');
        } else {
            IERC20Minimal(_asset).transfer(sendTo, _amount);
        }
    }

    function _stake(uint256 _amount, uint128 _lockTime, address _to) private returns (uint256 tokenId) {
        _increaseCumulative(uint128(block.timestamp));
        virtualRBCBalance += getAmountWithMultiplier(_amount, _lockTime);
        tokenId = _tokenId++;
        stakes[tokenId] = Stake({
            lockTime: _lockTime,
            lockStartTime: uint128(block.timestamp),
            amount: _amount,
            lastRewardGrowth: rewardGrowth
        });

        _mint(_to, tokenId);
    }

    function _increaseCumulative(uint128 currentTimestamp) private {
        if (emergencyStop) return;
        uint256 _rewardRate = rewardRate;
        uint256 _rewardReserve = _rewardRate > 0 ? rewardReserve : 0;
        if (virtualRBCBalance > 0) {
            if (_rewardReserve > 0) {
                uint256 reward = _rewardRate * (currentTimestamp - prevTimestamp);
                if (reward > _rewardReserve) reward = _rewardReserve;
                rewardReserve = _rewardReserve - reward;
                rewardGrowth += FullMath.mulDiv(reward, PRECISION, virtualRBCBalance);
            }
        }
        prevTimestamp = currentTimestamp;
    }

    function getAmountWithMultiplier(uint256 amount, uint128 lockTime) private pure returns (uint256) {
        if (lockTime == 30 days) return (10 * amount) / 10;
        if (lockTime == 90 days) return (10 * amount) / 10;
        if (lockTime == 180 days) return (12 * amount) / 10;
        if (lockTime == 270 days) return (15 * amount) / 10;
        if (lockTime == 360 days) return (20 * amount) / 10;
        revert('incorrect lock');
    }
}

