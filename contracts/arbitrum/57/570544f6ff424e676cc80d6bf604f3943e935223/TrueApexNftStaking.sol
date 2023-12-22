// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20Metadata.sol";
import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./SafeERC20.sol";

contract TrueApexNftStaking is Ownable, IERC721Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;
    uint256 private PRECISION_FACTOR;

    // Whether it is initialized
    bool public isInitialized;
    uint256 public duration = 365; // 365 days

    // The block number when staking starts.
    uint256 public startTime;
    // The block number when staking ends.
    uint256 public bonusEndTime;
    // tokens created per block.
    uint256[2] public rewardsPerSecond;
    // The block number of the last pool update
    uint256 public lastRewardTime;

    address public treasury = 0xE1f1dd010BBC2860F81c8F90Ea4E38dB949BB16F;
    uint256 public performanceFee = 0.00089 ether;

    // The staked token
    IERC721 public stakingNft;
    // The earned token
    address[2] public earnedTokens;
    // Accrued token per share
    uint256[2] public accTokenPerShares;
    uint256 public oneTimeLimit = 40;

    uint256 public totalStaked;
    uint256[2] private paidRewards;
    uint256[2] private shouldTotalPaid;

    struct UserInfo {
        uint256 amount; // number of staked NFTs
        uint256[] tokenIds; // staked tokenIds
        uint256[2] rewardDebt; // Reward debt
    }
    // Info of each user that stakes tokenIds

    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256[] tokenIds);
    event Withdraw(address indexed user, uint256[] tokenIds);
    event Claim(address indexed user, address indexed token, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256[] tokenIds);
    event AdminTokenRecovered(address tokenRecovered, uint256 amount);

    event NewStartAndEndBlocks(uint256 startTime, uint256 endBlock);
    event NewRewardsPerSecond(uint256[2] rewardsPerSecond);
    event RewardsStop(uint256 blockNumber);
    event EndBlockUpdated(uint256 blockNumber);

    event ServiceInfoUpadted(address addr, uint256 fee);
    event DurationUpdated(uint256 duration);

    constructor() {}

    /*
    * @notice Initialize the contract
    * @param _stakingNft: nft address to stake
    * @param _earnedToken: earned token address
    * @param _rewardsPerSecond: reward per block (in earnedToken)
    */
    function initialize(IERC721 _stakingNft, address[2] memory _earnedTokens, uint256[2] memory _rewardsPerSecond)
        external
        onlyOwner
    {
        require(!isInitialized, "Already initialized");

        // Make this contract initialized
        isInitialized = true;

        stakingNft = _stakingNft;
        earnedTokens = _earnedTokens;
        rewardsPerSecond = _rewardsPerSecond;

        PRECISION_FACTOR = uint256(10 ** 30);
    }

    /**
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _tokenIds: list of tokenId to stake
     */
    function deposit(uint256[] memory _tokenIds) external payable nonReentrant {
        require(startTime > 0 && startTime < block.timestamp, "Staking hasn't started yet");
        require(_tokenIds.length > 0, "must add at least one tokenId");
        require(_tokenIds.length <= oneTimeLimit, "cannot exceed one-time limit");

        _transferPerformanceFee();
        _updatePool();

        UserInfo storage user = userInfo[msg.sender];
        if (user.amount > 0) {
            _transferRewards(msg.sender, 0);
            _transferRewards(msg.sender, 1);
        }

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            stakingNft.safeTransferFrom(msg.sender, address(this), tokenId);
            user.tokenIds.push(tokenId);
        }
        user.amount += _tokenIds.length;
        user.rewardDebt[0] = (user.amount * accTokenPerShares[0]) / PRECISION_FACTOR;
        user.rewardDebt[1] = (user.amount * accTokenPerShares[1]) / PRECISION_FACTOR;

        totalStaked = totalStaked + _tokenIds.length;
        emit Deposit(msg.sender, _tokenIds);

        // update rate for block rewards
        _updateEthRewardRate();
    }

    /**
     * @notice Withdraw staked tokenIds and collect reward tokens
     * @param _amount: number of tokenIds to unstake
     */
    function withdraw(uint256 _amount) external payable nonReentrant {
        require(_amount > 0, "Amount should be greator than 0");
        require(_amount <= oneTimeLimit, "cannot exceed one-time limit");

        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");

        _transferPerformanceFee();
        _updatePool();

        if (user.amount > 0) {
            _transferRewards(msg.sender, 0);
            _transferRewards(msg.sender, 1);
        }

        uint256[] memory _tokenIds = new uint256[](_amount);
        for (uint256 i = 0; i < _amount; i++) {
            uint256 tokenId = user.tokenIds[user.tokenIds.length - 1];
            user.tokenIds.pop();

            _tokenIds[i] = tokenId;
            stakingNft.safeTransferFrom(address(this), msg.sender, tokenId);
        }
        user.amount = user.amount - _amount;
        user.rewardDebt[0] = (user.amount * accTokenPerShares[0]) / PRECISION_FACTOR;
        user.rewardDebt[1] = (user.amount * accTokenPerShares[1]) / PRECISION_FACTOR;

        totalStaked = totalStaked - _amount;
        emit Withdraw(msg.sender, _tokenIds);

        _updateEthRewardRate();
    }

    function claimReward(uint8 _index) external payable nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        _transferPerformanceFee();
        _updatePool();

        if (user.amount > 0) {
            _transferRewards(msg.sender, _index);
            user.rewardDebt[_index] = (user.amount * accTokenPerShares[_index]) / PRECISION_FACTOR;
        }
        _updateEthRewardRate();
    }

    function claimRewardAll() external payable nonReentrant {
        _transferPerformanceFee();
        _updatePool();

        if (userInfo[msg.sender].amount > 0) {
            _transferRewards(msg.sender, 0);
            _transferRewards(msg.sender, 1);

            UserInfo storage user = userInfo[msg.sender];
            user.rewardDebt[0] = (user.amount * accTokenPerShares[0]) / PRECISION_FACTOR;
            user.rewardDebt[1] = (user.amount * accTokenPerShares[1]) / PRECISION_FACTOR;
        }
        _updateEthRewardRate();
    }

    function _transferRewards(address _user, uint8 _index) internal {
        UserInfo storage user = userInfo[_user];
        uint256 pending = (user.amount * accTokenPerShares[_index]) / PRECISION_FACTOR - user.rewardDebt[_index];
        if (pending == 0) return;

        require(availableRewardTokens(_index) >= pending, "Insufficient reward tokens");
        paidRewards[_index] += pending;

        _transferTokens(earnedTokens[_index], _user, pending);
        emit Claim(_user, earnedTokens[_index], pending);
    }

    function _transferTokens(address _token, address _to, uint256 _amount) internal {
        if (_token == address(0x0)) {
            payable(_to).transfer(_amount);
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }
    }

    function _updateEthRewardRate() internal {
        if (bonusEndTime <= block.timestamp) return;

        uint256 remainRewards = availableRewardTokens(1) + paidRewards[1];
        if (remainRewards > shouldTotalPaid[1]) {
            remainRewards = remainRewards - shouldTotalPaid[1];

            uint256 remainBlocks = bonusEndTime - block.timestamp;
            rewardsPerSecond[1] = remainRewards / remainBlocks;
            emit NewRewardsPerSecond(rewardsPerSecond);
        }
    }

    /**
     * @notice Withdraw staked NFTs without caring about rewards
     * @dev Needs to be for emergency.
     */
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 _amount = user.amount;
        if (_amount > oneTimeLimit) _amount = oneTimeLimit;

        uint256[] memory _tokenIds = new uint256[](_amount);
        for (uint256 i = 0; i < _amount; i++) {
            uint256 tokenId = user.tokenIds[user.tokenIds.length - 1];
            user.tokenIds.pop();

            _tokenIds[i] = tokenId;
            stakingNft.safeTransferFrom(address(this), msg.sender, tokenId);
        }
        user.amount = user.amount - _amount;
        user.rewardDebt[0] = (user.amount * accTokenPerShares[0]) / PRECISION_FACTOR;
        user.rewardDebt[1] = (user.amount * accTokenPerShares[1]) / PRECISION_FACTOR;
        totalStaked = totalStaked - _amount;

        emit EmergencyWithdraw(msg.sender, _tokenIds);
    }

    function stakedInfo(address _user) external view returns (uint256, uint256[] memory) {
        return (userInfo[_user].amount, userInfo[_user].tokenIds);
    }

    /**
     * @notice Available amount of reward token
     */
    function availableRewardTokens(uint8 _index) public view returns (uint256) {
        if (earnedTokens[_index] == address(0x0)) return address(this).balance;
        return IERC20(earnedTokens[_index]).balanceOf(address(this));
    }

    function insufficientRewards() external view returns (uint256) {
        uint256 adjustedShouldTotalPaid = shouldTotalPaid[0];
        uint256 remainRewards = availableRewardTokens(0) + paidRewards[0];

        if (startTime == 0) {
            adjustedShouldTotalPaid += rewardsPerSecond[0] * duration * 86400;
        } else {
            uint256 remainBlocks = _getMultiplier(lastRewardTime, bonusEndTime);
            adjustedShouldTotalPaid += rewardsPerSecond[0] * remainBlocks;
        }

        if (remainRewards >= adjustedShouldTotalPaid) return 0;
        return adjustedShouldTotalPaid - remainRewards;
    }

    /**
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @param _index: index of earning token (0 - earning token, 1 - eth)
     * @return Pending reward for a given user
     */
    function pendingReward(address _user, uint8 _index) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];

        uint256 adjustedTokenPerShare = accTokenPerShares[_index];
        if (block.timestamp > lastRewardTime && totalStaked > 0 && lastRewardTime > 0) {
            uint256 multiplier = _getMultiplier(lastRewardTime, block.timestamp);
            uint256 rewards = multiplier * rewardsPerSecond[_index];

            adjustedTokenPerShare += (rewards * PRECISION_FACTOR) / totalStaked;
        }

        return (user.amount * adjustedTokenPerShare) / PRECISION_FACTOR - user.rewardDebt[_index];
    }

    /**
     * Admin Methods
     */
    function increaseEmissionRate(uint256 _amount) external onlyOwner {
        require(startTime > 0, "pool is not started");
        require(bonusEndTime > block.timestamp, "pool was already finished");
        require(_amount > 0, "invalid amount");

        _updatePool();

        IERC20(earnedTokens[0]).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 remainRewards = availableRewardTokens(0) + paidRewards[0];
        if (remainRewards > shouldTotalPaid[0]) {
            remainRewards = remainRewards - shouldTotalPaid[0];

            uint256 remainBlocks = bonusEndTime - block.timestamp;
            rewardsPerSecond[0] = remainRewards / remainBlocks;
            emit NewRewardsPerSecond(rewardsPerSecond);
        }
    }

    /*
    * @notice Withdraw reward token
    * @dev Only callable by owner. Needs to be for emergency.
    */
    function emergencyRewardWithdraw(uint256 _amount, uint8 _index) external onlyOwner {
        require(block.timestamp > bonusEndTime, "Pool is running");
        if (_index == 0) {
            require(availableRewardTokens(0) >= _amount, "Insufficient reward tokens");
            if (_amount == 0) _amount = availableRewardTokens(0);
            IERC20(earnedTokens[0]).safeTransfer(address(msg.sender), _amount);
        } else {
            if (earnedTokens[1] == address(0x0)) {
                payable(msg.sender).transfer(address(this).balance);
            } else {
                IERC20(earnedTokens[1]).safeTransfer(msg.sender, IERC20(earnedTokens[1]).balanceOf(address(this)));
            }
        }
    }

    function startReward() external onlyOwner {
        require(startTime == 0, "Pool was already started");

        startTime = block.timestamp + 5 * 60; // 5 mins
        bonusEndTime = startTime + duration * 86400;
        lastRewardTime = startTime;

        emit NewStartAndEndBlocks(startTime, bonusEndTime);
    }

    function stopReward() external onlyOwner {
        _updatePool();

        uint256 remainRewards = availableRewardTokens(0) + paidRewards[0];
        if (remainRewards > shouldTotalPaid[0]) {
            remainRewards = remainRewards - shouldTotalPaid[0];
            IERC20(earnedTokens[0]).transfer(msg.sender, remainRewards);
        }

        remainRewards = address(this).balance;
        if (earnedTokens[1] != address(0x0)) {
            remainRewards = IERC20(earnedTokens[1]).balanceOf(address(this));
        }

        remainRewards += paidRewards[1];
        if (remainRewards > shouldTotalPaid[1]) {
            remainRewards = remainRewards - shouldTotalPaid[1];
            _transferTokens(earnedTokens[1], msg.sender, remainRewards);
        }

        bonusEndTime = block.timestamp;
        emit RewardsStop(bonusEndTime);
    }

    function updateEndBlock(uint256 _endBlock) external onlyOwner {
        require(startTime > 0, "Pool is not started");
        require(bonusEndTime > block.timestamp, "Pool was already finished");
        require(_endBlock > block.timestamp && _endBlock > startTime, "Invalid end block");

        bonusEndTime = _endBlock;
        emit EndBlockUpdated(_endBlock);
    }

    /**
     * @notice Update reward per block
     * @dev Only callable by owner.
     * @param _rewardsPerSecond: the reward per block
     * @param _index: index of reward token
     */
    function updaterewardsPerSecond(uint256 _rewardsPerSecond, uint8 _index) external onlyOwner {
        _updatePool();
        rewardsPerSecond[_index] = _rewardsPerSecond;
        emit NewRewardsPerSecond(rewardsPerSecond);
    }

    function setDuration(uint256 _duration) external onlyOwner {
        require(_duration >= 30, "lower limit reached");

        _updatePool();
        duration = _duration;
        if (startTime > 0) {
            bonusEndTime = startTime + duration * 86400;
            require(bonusEndTime > block.timestamp, "invalid duration");
        }
        emit DurationUpdated(_duration);
    }

    function setServiceInfo(address _treasury, uint256 _fee) external {
        require(msg.sender == treasury, "setServiceInfo: FORBIDDEN");
        require(_treasury != address(0x0), "Invalid address");

        treasury = _treasury;
        performanceFee = _fee;
        emit ServiceInfoUpadted(_treasury, _fee);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _token: the address of the token to withdraw
     * @dev This function is only callable by admin.
     */
    function rescueTokens(address _token) external onlyOwner {
        require(_token != address(earnedTokens[0]), "Cannot be reward token");
        require(_token != address(earnedTokens[1]), "Cannot be reward token");

        uint256 amount = address(this).balance;
        if (_token == address(0x0)) {
            payable(msg.sender).transfer(amount);
        } else {
            amount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(address(msg.sender), amount);
        }

        emit AdminTokenRecovered(_token, amount);
    }

    /*
    * @notice Update reward variables of the given pool to be up-to-date.
    */
    function _updatePool() internal {
        if (block.timestamp <= lastRewardTime || lastRewardTime == 0) return;
        if (totalStaked == 0) {
            lastRewardTime = block.timestamp;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardTime, block.timestamp);
        uint256 _reward = multiplier * rewardsPerSecond[0];
        accTokenPerShares[0] += (_reward * PRECISION_FACTOR) / totalStaked;
        shouldTotalPaid[0] += _reward;

        _reward = multiplier * rewardsPerSecond[1];
        accTokenPerShares[1] += (_reward * PRECISION_FACTOR) / totalStaked;
        shouldTotalPaid[1] += _reward;

        lastRewardTime = block.timestamp;
    }

    /**
     * @notice Return reward multiplier over the given _from to _to block.
     * @param _from: block to start
     * @param _to: block to finish
     */
    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= bonusEndTime) {
            return _to - _from;
        } else if (_from >= bonusEndTime) {
            return 0;
        } else {
            return bonusEndTime - _from;
        }
    }

    function _transferPerformanceFee() internal {
        require(msg.value >= performanceFee, "should pay small gas");

        payable(treasury).transfer(performanceFee);
        if (msg.value > performanceFee) {
            payable(msg.sender).transfer(msg.value - performanceFee);
        }
    }

    /**
     * onERC721Received(address operator, address from, uint256 tokenId, bytes data) → bytes4
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external view override returns (bytes4) {
        require(msg.sender == address(stakingNft), "not enabled NFT");
        return _ERC721_RECEIVED;
    }

    receive() external payable {}
}

