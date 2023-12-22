pragma solidity ^0.8.18;

import "./Pausable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Context.sol";
import "./SafeMath.sol";

interface Token {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract StakeDTL is Pausable, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    
    Token dtlToken;
    Token rewardToken;

    uint256[3] public lockPeriods = [604800, 2592000, 7776000];
    uint256[3] public sharesPerToken = [20, 15, 10];
    uint256 private constant ONE_DAY_IN_SECONDS = 24 * 60 * 60;


    uint256 public totalShares;
    uint256 public totalRewards;
    uint256 public totalStakers;
    uint256 public lastRewardDistribution;
    uint256 public rewardPercentage = 5;
    uint256 private constant PRECISION = 10**18;
    address[] public userAddresses;


    struct StakeInfo {
        uint256 startTS;
        uint256 endTS;
        uint256 amount;
        uint256 shares;
        uint8 lockPeriodIndex;
        bool expired;
    }

    event Staked(address indexed from, uint256 amount, uint8 lockPeriodIndex);
    event Claimed(address indexed from, uint256 amount);

    mapping(address => mapping(bytes32 => StakeInfo)) public stakeInfos;
    mapping(address => uint256) public userTotalShares;
    mapping(address => uint256) public unclaimedRewards;
    mapping(address => uint256) public claimedRewards;
    mapping(address => bytes32[]) public stakeIds;
    mapping(address => DistributionData) public distributionData;

struct DistributionData {
    uint256 shares;
    uint256 lastUpdated;
}


    constructor(Token _dtlTokenAddress, Token _rewardTokenAddress) {
        require(address(_dtlTokenAddress) != address(0), "DTL Token Address cannot be address 0");
        require(address(_rewardTokenAddress) != address(0), "Reward Token Address cannot be address 0");

        dtlToken = _dtlTokenAddress;
        rewardToken = _rewardTokenAddress;

        totalShares = 0;
        totalRewards = 0;
        lastRewardDistribution = block.timestamp;
    }

    function addReward(uint256 amount) external onlyOwner {
        require(rewardToken.transferFrom(_msgSender(), address(this), amount), "Token transfer failed!");
        totalRewards += amount;
    }

    function divCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "division by zero");
        return a.mul(PRECISION).add(b.sub(1)).div(b); // Support precision
    }


function updateData(uint256 startIndex, uint256 limit) external onlyOwner {
    for (uint256 i = startIndex; i < userAddresses.length && i < startIndex + limit; i++) {
        address staker = userAddresses[i];
        if(block.timestamp > distributionData[staker].lastUpdated + ONE_DAY_IN_SECONDS) {
            uint256 stakerActiveShares = calculateActiveShares(staker);
            distributionData[staker] = DistributionData({
                shares: stakerActiveShares,
                lastUpdated: block.timestamp
            });
        }
    }
}


function selfUpdateData() external {
    address staker = _msgSender();
    uint256 stakerActiveShares = calculateActiveShares(staker);
    distributionData[staker] = DistributionData({
        shares: stakerActiveShares,
        lastUpdated: block.timestamp
    });
}

function _selfUpdateData(address staker) internal {
    uint256 stakerActiveShares = calculateActiveShares(staker);
    distributionData[staker] = DistributionData({
        shares: stakerActiveShares,
        lastUpdated: block.timestamp
    });
}

function calculateActiveShares(address staker) internal view returns(uint256) {
    uint256 stakerActiveShares = 0;
    uint256 stakeCount = stakeIds[staker].length;
    for (uint256 j = 0; j < stakeCount; j++) {
        bytes32 stakeId = stakeIds[staker][j];
        StakeInfo storage stakeInfo = stakeInfos[staker][stakeId];
        if (stakeInfo.endTS >= block.timestamp && !stakeInfo.expired) {
            stakerActiveShares = stakerActiveShares.add(stakeInfo.shares);
        }
    }
    return stakerActiveShares;
}


function distributeRewards() internal {
    if (totalShares == 0) {
        return;
    }

    uint256 elapsedTime = block.timestamp.sub(lastRewardDistribution);

    if (elapsedTime > 0) {
        uint256 rewardsForTwentyFourHours = totalRewards.mul(rewardPercentage).div(100);
        uint256 rewardsToDistribute = divCeil(rewardsForTwentyFourHours.mul(elapsedTime).div(86400), PRECISION);

        require(rewardToken.balanceOf(address(this)) >= rewardsToDistribute, "Insufficient reward token balance");

        uint256 rewardsPerShare = divCeil(rewardsToDistribute, totalShares);

        totalRewards = totalRewards.sub(rewardsToDistribute);
        lastRewardDistribution = block.timestamp;

        for (uint256 i = 0; i < userAddresses.length; i++) {
            address staker = userAddresses[i];
            uint256 stakerShares = distributionData[staker].shares;

            if (stakerShares > 0) {
                uint256 stakerReward = stakerShares.mul(rewardsPerShare).div(PRECISION);
                unclaimedRewards[staker] = unclaimedRewards[staker].add(stakerReward);
            }
        }
    }
}

function claimAllRewards() external nonReentrant {
        distributeRewards();

        uint256 stakerUnclaimedRewards = unclaimedRewards[_msgSender()];
        require(stakerUnclaimedRewards > 0, "No unclaimed rewards");
        require(rewardToken.transfer(_msgSender(), stakerUnclaimedRewards), "Token transfer failed!");
        claimedRewards[_msgSender()] += stakerUnclaimedRewards;

        unclaimedRewards[_msgSender()] = 0;
        _selfUpdateData(_msgSender());
        emit Claimed(_msgSender(), stakerUnclaimedRewards);
    }

    function stakeToken(uint256 stakeAmount, uint8 lockPeriodIndex) external whenNotPaused nonReentrant {
        distributeRewards();
         if (userTotalShares[_msgSender()] == 0)  {
        userAddresses.push(_msgSender());
        }
        require(stakeAmount > 0, "Stake amount should be correct");
        require(lockPeriodIndex < lockPeriods.length, "Invalid lock period");
        require(dtlToken.balanceOf(_msgSender()) >= stakeAmount, "Insufficient Balance");
        require(dtlToken.transferFrom(_msgSender(), address(this), stakeAmount), "Token transfer failed!");

        uint256 shares = stakeAmount / sharesPerToken[lockPeriodIndex];
        totalShares += shares;
        userTotalShares[_msgSender()] += shares;

        bytes32 stakeId = keccak256(abi.encodePacked(_msgSender(), block.timestamp, stakeAmount, lockPeriodIndex));
        stakeIds[_msgSender()].push(stakeId);

        StakeInfo memory stakeInfo = StakeInfo({
            startTS: block.timestamp,
            endTS: block.timestamp.add(lockPeriods[lockPeriodIndex]),
            amount: stakeAmount,
            shares: shares,
            lockPeriodIndex: lockPeriodIndex,
            expired: false
        });

        stakeInfos[_msgSender()][stakeId] = stakeInfo;
        _selfUpdateData(_msgSender());
        emit Staked(_msgSender(), stakeAmount, lockPeriodIndex);
    }

  function withdrawStake(bytes32 stakeId) external nonReentrant {
    require(stakeInfos[_msgSender()][stakeId].endTS <= block.timestamp, "Staking period not over");
    require(stakeInfos[_msgSender()][stakeId].expired == false, "Stake is already expired");

    uint256 stakeAmount = stakeInfos[_msgSender()][stakeId].amount;
    uint256 shares = stakeInfos[_msgSender()][stakeId].shares;

    totalShares -= shares;
    userTotalShares[_msgSender()] -= shares;

    stakeInfos[_msgSender()][stakeId].expired = true;
    _selfUpdateData(_msgSender());
    require(dtlToken.transfer(_msgSender(), stakeAmount), "Token transfer failed!");
}

function unstake(uint256 stakeIndex) external nonReentrant {
    require(stakeIndex < stakeIds[_msgSender()].length, "Invalid stake index");

    bytes32 stakeId = stakeIds[_msgSender()][stakeIndex];
    require(stakeInfos[_msgSender()][stakeId].endTS <= block.timestamp, "Staking period not over");
    require(stakeInfos[_msgSender()][stakeId].expired == false, "Stake is already expired");

    uint256 stakeAmount = stakeInfos[_msgSender()][stakeId].amount;
    uint256 shares = stakeInfos[_msgSender()][stakeId].shares;

    totalShares -= shares;
    userTotalShares[_msgSender()] -= shares;

    stakeInfos[_msgSender()][stakeId].expired = true;
    _selfUpdateData(_msgSender());

    require(dtlToken.transfer(_msgSender(), stakeAmount), "Token transfer failed!");
}



    function setRewardPercentage(uint256 newRewardPercentage) external onlyOwner {
        require(newRewardPercentage > 0 && newRewardPercentage <= 100, "Invalid reward percentage");
        rewardPercentage = newRewardPercentage;
    }

    function pauseStaking() external onlyOwner {
        _pause();
    }

    function getStakeIds(address user) external view returns (bytes32[] memory) {
    return stakeIds[user];
    }

    function stakeDetails(address user) external view returns (StakeInfo[] memory) {
    bytes32[] memory ids = stakeIds[user];
    StakeInfo[] memory stakes = new StakeInfo[](ids.length);

    for (uint256 i = 0; i < ids.length; i++) {
        stakes[i] = stakeInfos[user][ids[i]];
    }

    return stakes;
}

   function getCurrentTime() public view returns (uint256) {
        return block.timestamp;
    }


    function unpauseStaking() external onlyOwner {
        _unpause();
    }

    function emergencyClearRewards() external onlyOwner {
        totalRewards = 0;
        for (uint256 i = 0; i < userAddresses.length; i++) {
            address staker = userAddresses[i];
            unclaimedRewards[staker] = 0;
        }
    }

    function emergencySetExpireNow() external onlyOwner {
        for (uint256 i = 0; i < userAddresses.length; i++) {
            address staker = userAddresses[i];
            uint256 stakeCount = stakeIds[staker].length;
            for (uint256 j = 0; j < stakeCount; j++) {
                bytes32 stakeId = stakeIds[staker][j];
                StakeInfo storage stakeInfo = stakeInfos[staker][stakeId];
                if (!stakeInfo.expired) {
                    stakeInfo.endTS = block.timestamp;
                }
            }
        }
    }

    function emergencyWithdraw(uint256 amount) external onlyOwner {
        require(amount > 0, "Withdrawal amount must be greater than zero");
        require(rewardToken.balanceOf(address(this)) >= amount, "Insufficient reward token balance");

        require(rewardToken.transfer(owner(), amount), "Token transfer failed!");
        emit EmergencyWithdraw(owner(), amount);
    }

    event EmergencyWithdraw(address indexed to, uint256 amount);
}


