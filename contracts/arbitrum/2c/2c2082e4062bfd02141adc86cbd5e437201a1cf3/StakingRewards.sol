// SPDX-License-Identifier: GPL-3.0
/*                            ******@@@@@@@@@**@*                               
                        ***@@@@@@@@@@@@@@@@@@@@@@**                             
                     *@@@@@@**@@@@@@@@@@@@@@@@@*@@@*                            
                  *@@@@@@@@@@@@@@@@@@@*@@@@@@@@@@@*@**                          
                 *@@@@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@*                         
                **@@@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@@@**                       
                **@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@@@@@@@*                      
                **@@@@@@@@@@@@@@@@*************************                    
                **@@@@@@@@***********************************                   
                 *@@@***********************&@@@@@@@@@@@@@@@****,    ******@@@@*
           *********************@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@************* 
      ***@@@@@@@@@@@@@@@*****@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@****@@*********      
   **@@@@@**********************@@@@*****************#@@@@**********            
  *@@******************************************************                     
 *@************************************                                         
 @*******************************                                               
 *@*************************                                                    
   ********************* 
   
    /$$$$$                                               /$$$$$$$   /$$$$$$   /$$$$$$ 
   |__  $$                                              | $$__  $$ /$$__  $$ /$$__  $$
      | $$  /$$$$$$  /$$$$$$$   /$$$$$$   /$$$$$$$      | $$  \ $$| $$  \ $$| $$  \ $$
      | $$ /$$__  $$| $$__  $$ /$$__  $$ /$$_____/      | $$  | $$| $$$$$$$$| $$  | $$
 /$$  | $$| $$  \ $$| $$  \ $$| $$$$$$$$|  $$$$$$       | $$  | $$| $$__  $$| $$  | $$
| $$  | $$| $$  | $$| $$  | $$| $$_____/ \____  $$      | $$  | $$| $$  | $$| $$  | $$
|  $$$$$$/|  $$$$$$/| $$  | $$|  $$$$$$$ /$$$$$$$/      | $$$$$$$/| $$  | $$|  $$$$$$/
 \______/  \______/ |__/  |__/ \_______/|_______/       |_______/ |__/  |__/ \______/                                      
*/
pragma solidity ^0.8.2;

// Libraries
import "./Math.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";

// Interfaces
import "./IERC20.sol";
import "./IStakingRewards.sol";

// Contracts
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./RewardsDistributionRecipient.sol";

contract StakingRewards is
    RewardsDistributionRecipient,
    ReentrancyGuard,
    Ownable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    /// Jones address
    IERC20 public rewardsTokenJONES;

    /// Staking token address
    IERC20 public stakingToken;

    /// Factor by which the rewards are boosted
    uint256 public boost = 0;

    /// Farming period end timestamp
    uint256 public periodFinish = 0;

    /// Boosted farming period end timestamp
    uint256 public boostedFinish = 0;

    /// JONES reward rate
    uint256 public rewardRateJONES = 0;

    /// Duration of rewards
    uint256 public rewardsDuration;

    /// Last time updated
    uint256 public lastUpdateTime;

    /// Reward for each token stored
    uint256 public rewardPerTokenStoredJONES;

    /// Boosted time period
    uint256 public boostedTimePeriod;

    /// ID for this farm
    uint256 public id;

    /// Mapping of addresses whitelisted for interaction
    mapping(address => bool) public whitelistedContracts;

    ///
    mapping(address => uint256) public userJONESRewardPerTokenPaid;

    ///
    mapping(address => uint256) public rewardsJONES;

    /// User balances
    mapping(address => uint256) private _balances;

    /// Total staked tokens
    uint256 private _totalSupply;

    /* ========== CONSTRUCTOR ========== */

    /// @param _rewardsDistribution Factory address
    /// @param _rewardsTokenJONES Address of the JONES token
    /// @param _stakingToken Address of the staking token
    /// @param _rewardsDuration Duration of the rewards
    /// @param _boost Boost factor
    /// @param _boostedTimePeriod Boosted time period
    /// @param _id ID of the farm
    constructor(
        address _rewardsDistribution,
        address _rewardsTokenJONES,
        address _stakingToken,
        uint256 _rewardsDuration,
        uint256 _boostedTimePeriod,
        uint256 _boost,
        uint256 _id
    ) Ownable() {
        rewardsTokenJONES = IERC20(_rewardsTokenJONES);
        stakingToken = IERC20(_stakingToken);
        rewardsDistribution = _rewardsDistribution;
        rewardsDuration = _rewardsDuration;
        boostedTimePeriod = _boostedTimePeriod;
        boost = _boost;
        id = _id;
    }

    /* ========== VIEWS ========== */

    /// @param _addr Address of the user
    /// @return true if address is a contract
    function isContract(address _addr) public view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    /// @return number of total staked tokens
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @param _account Address of the user
    /// @return number of tokens staked by the user
    function balanceOf(address _account) external view returns (uint256) {
        return _balances[_account];
    }

    /// @return when farming period ends
    function lastTimeRewardApplicable() public view returns (uint256) {
        uint256 timeApp = Math.min(block.timestamp, periodFinish);
        return timeApp;
    }

    /// @return Jones reward rate
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            // If no tokens are staked, reward is 0
            uint256 perTokenRateJONES = rewardPerTokenStoredJONES;
            return (perTokenRateJONES);
        }
        if (block.timestamp < boostedFinish) {
            // If boosted time period is active, reward is boosted
            uint256 perTokenRateJONES = rewardPerTokenStoredJONES.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRateJONES.mul(boost).div(100))
                    .mul(1e18)
                    .div(_totalSupply)
            );
            return perTokenRateJONES;
        } else {
            // if last update was before boost period ended, reward is boosted + normal
            if (lastUpdateTime < boostedFinish) {
                uint256 perTokenRateJONES = rewardPerTokenStoredJONES
                    .add(
                        boostedFinish
                            .sub(lastUpdateTime)
                            .mul(rewardRateJONES.mul(boost).div(100))
                            .mul(1e18)
                            .div(_totalSupply)
                    )
                    .add(
                        lastTimeRewardApplicable()
                            .sub(boostedFinish)
                            .mul(rewardRateJONES)
                            .mul(1e18)
                            .div(_totalSupply)
                    );

                return perTokenRateJONES;
            } else {
                // If boosted time period is not active, reward is normal
                uint256 perTokenRateJONES = rewardPerTokenStoredJONES.add(
                    lastTimeRewardApplicable()
                        .sub(lastUpdateTime)
                        .mul(rewardRateJONES)
                        .mul(1e18)
                        .div(_totalSupply)
                );
                return perTokenRateJONES;
            }
        }
    }

    /// @param _account Address of the user
    /// @return JONEStokensEarned tokens earned by the user
    function earned(address _account)
        public
        view
        returns (uint256 JONEStokensEarned)
    {
        uint256 perTokenRateJONES;
        perTokenRateJONES = rewardPerToken();
        JONEStokensEarned = _balances[_account]
            .mul(perTokenRateJONES.sub(userJONESRewardPerTokenPaid[_account]))
            .div(1e18)
            .add(rewardsJONES[_account]);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// Stake tokens
    /// @param _amount Amount of tokens to stake
    function stake(uint256 _amount)
        external
        payable
        isEligibleSender
        nonReentrant
        updateReward(msg.sender)
    {
        require(_amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply.add(_amount);
        _balances[msg.sender] = _balances[msg.sender].add(_amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    /// Unstake tokens
    /// @param _amount Amount of tokens to unstake
    function withdraw(uint256 _amount)
        public
        nonReentrant
        updateReward(msg.sender)
    {
        require(_amount > 0, "Cannot withdraw 0");
        require(_amount <= _balances[msg.sender], "Insufficent balance");
        _totalSupply = _totalSupply.sub(_amount);
        _balances[msg.sender] = _balances[msg.sender].sub(_amount);
        stakingToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    /// Claim certain amount of rewards
    /// @param _amountJONES Amount of tokens to claim
    function withdrawRewardTokens(uint256 _amountJONES)
        public
        onlyOwner
        returns (uint256)
    {
        address OwnerAddress = owner();
        if (OwnerAddress == msg.sender) {
            IERC20(rewardsTokenJONES).safeTransfer(OwnerAddress, _amountJONES);
        }
        return _amountJONES;
    }

    /// Compound rewards
    function compound() public nonReentrant updateReward(msg.sender) {
        uint256 rewardJONES = rewardsJONES[msg.sender];
        require(rewardJONES > 0, "stake address not found");
        require(
            rewardsTokenJONES == stakingToken,
            "Can't stake the reward token."
        );
        rewardsJONES[msg.sender] = 0;
        _totalSupply = _totalSupply.add(rewardJONES);
        _balances[msg.sender] = _balances[msg.sender].add(rewardJONES);
        emit RewardCompounded(msg.sender, rewardJONES);
    }

    /// Claim all rewards
    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 rewardJONES = rewardsJONES[msg.sender];
        require(rewardJONES > 0, "can not withdraw 0 JONES reward");
        rewardsJONES[msg.sender] = 0;
        rewardsTokenJONES.safeTransfer(msg.sender, rewardJONES);
        emit RewardPaid(msg.sender, rewardJONES);
    }

    /// Exit from farm (unstake and claim all rewards)
    function exit() external {
        getReward();
        withdraw(_balances[msg.sender]);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @param _rewardJONES Amount of JONES to be rewarded
    function notifyRewardAmount(uint256 _rewardJONES)
        external
        override
        onlyRewardsDistribution
        setReward(address(0))
    {
        if (periodFinish == 0) {
            rewardRateJONES = _rewardJONES.div(
                rewardsDuration.add(boostedTimePeriod)
            );

            lastUpdateTime = block.timestamp;
            periodFinish = block.timestamp.add(rewardsDuration);
            boostedFinish = block.timestamp.add(boostedTimePeriod);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftoverJONES = remaining.mul(rewardRateJONES);
            rewardRateJONES = _rewardJONES.add(leftoverJONES).div(
                rewardsDuration
            );
            lastUpdateTime = block.timestamp;
            periodFinish = block.timestamp.add(rewardsDuration);
        }
        emit RewardAdded(_rewardJONES);
    }

    /// @param _contract Whitelist contract for interaction
    function addToContractWhitelist(address _contract)
        external
        onlyOwner
        returns (bool)
    {
        require(
            isContract(_contract),
            "StakingRewards: Address must be a contract address"
        );
        require(
            !whitelistedContracts[_contract],
            "StakingRewards: Contract already whitelisted"
        );

        whitelistedContracts[_contract] = true;

        emit AddToContractWhitelist(_contract);

        return true;
    }

    /// @param _contract Blacklist contract for interaction
    function removeFromContractWhitelist(address _contract)
        external
        onlyOwner
        returns (bool)
    {
        require(
            whitelistedContracts[_contract],
            "StakingRewards: Contract not whitelisted"
        );

        whitelistedContracts[_contract] = false;

        emit RemoveFromContractWhitelist(_contract);

        return true;
    }

    /* ========== MODIFIERS ========== */

    // Modifier is eligible sender modifier
    modifier isEligibleSender() {
        if (isContract(msg.sender))
            require(
                whitelistedContracts[msg.sender],
                "StakingRewards: Contract must be whitelisted"
            );
        _;
    }

    // Modifier Set Reward modifier
    modifier setReward(address _account) {
        rewardPerTokenStoredJONES = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (_account != address(0)) {
            rewardsJONES[_account] = earned(_account);
            userJONESRewardPerTokenPaid[_account] = rewardPerTokenStoredJONES;
        }
        _;
    }

    // Modifier *Update Reward modifier*
    modifier updateReward(address _account) {
        (rewardPerTokenStoredJONES) = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (_account != address(0)) {
            rewardsJONES[_account] = earned(_account);
            userJONESRewardPerTokenPaid[_account] = rewardPerTokenStoredJONES;
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardUpdated(uint256 rewardJONES);
    event RewardAdded(uint256 rewardJONES);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardCompounded(address indexed user, uint256 rewardJONES);
    event AddToContractWhitelist(address indexed _contract);
    event RemoveFromContractWhitelist(address indexed _contract);
}

interface IUniswapV2ERC20 {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

