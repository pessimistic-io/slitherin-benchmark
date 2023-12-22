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
import "./SafeMath.sol";
import "./SafeERC20.sol";

// Interfaces
import "./IERC20.sol";

// Contracts
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./StakingRewards.sol";
import "./IStakingRewards.sol";

contract StakingRewardsFactory is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// immutables
    address public immutable rewardsTokenJones;
    uint256 public immutable stakingRewardsGenesis;

    /// the staking tokens for which the rewards contract has been deployed
    uint256[] public stakingID;

    // info about rewards for a particular staking token
    struct StakingRewardsInfo {
        address stakingRewards;
        uint256 rewardAmountJONES;
        uint256 id;
    }

    /// rewards info by staking token
    /// @dev staking IDs start from 1
    mapping(uint256 => StakingRewardsInfo)
        public stakingRewardsInfoByStakingToken;

    /// @param _rewardsTokenJones address of the rewards token
    /// @param _stakingRewardsGenesis timestamp of the genesis block
    constructor(address _rewardsTokenJones, uint256 _stakingRewardsGenesis)
        Ownable()
    {
        require(
            _stakingRewardsGenesis >= block.timestamp,
            "Factory constructor: genesis too soon"
        );
        rewardsTokenJones = _rewardsTokenJones;
        stakingRewardsGenesis = _stakingRewardsGenesis;
    }

    /// deploy a staking reward contract for the staking token, and store the reward amount
    /// the reward will be distributed to the staking reward contract no sooner than the genesis
    /// @param _stakingToken address of token to be staked
    /// @param _rewardAmountJONES amount of rewards to be distributed by the staking rewards contract
    /// @param _rewardsDuration duration of rewards
    /// @param _boostedTimePeriod period of time during which the rewards are boosted
    /// @param _boost factor by which the rewards are boosted
    /// @param _id staking ID for this farm
    function deploy(
        address _stakingToken,
        uint256 _rewardAmountJONES,
        uint256 _rewardsDuration,
        uint256 _boostedTimePeriod,
        uint256 _boost,
        uint256 _id
    ) public onlyOwner {
        StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[_id];
        require(info.id != _id, "Factory: StakingID already taken");
        require(_rewardAmountJONES > 0, "Factory: Invalid JONES reward amount");
        info.stakingRewards = address(
            new StakingRewards(
                address(this),
                rewardsTokenJones,
                _stakingToken,
                _rewardsDuration,
                _boostedTimePeriod,
                _boost,
                _id
            )
        );
        info.rewardAmountJONES = _rewardAmountJONES;
        info.id = _id;
        stakingID.push(_id);
    }

    /// Withdraw tokens to multisig
    /// @param _amountJONES amount of JONES to withdraw
    function withdrawRewardToken(uint256 _amountJONES)
        public
        onlyOwner
        returns (uint256)
    {
        address ownerAddress = owner();
        if (ownerAddress == msg.sender) {
            IERC20(rewardsTokenJones).transfer(ownerAddress, _amountJONES);
        }
        return _amountJONES;
    }

    /// Withdraw tokens from a staking rewards contract
    /// @param _amountJONES amount of JONES to withdraw
    /// @param _id staking ID for this farm
    function withdrawRewardTokensFromContract(uint256 _amountJONES, uint256 _id)
        public
        onlyOwner
    {
        address ownerAddress = owner();
        if (ownerAddress == msg.sender) {
            StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[
                _id
            ];
            require(
                info.stakingRewards != address(0),
                "Factory notifyRewardAmount: not deployed"
            );
            StakingRewards(info.stakingRewards).withdrawRewardTokens(
                _amountJONES
            );
        }
    }

    /// notify reward amount for an individual staking token.
    /// this is a fallback in case the notifyRewardAmounts costs too much gas to call for all contracts
    /// @param _id staking ID for this farm
    function notifyRewardAmount(uint256 _id) public onlyOwner {
        require(
            block.timestamp >= stakingRewardsGenesis,
            "Factory notifyRewardAmount: not ready"
        );
        StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[_id];
        require(
            info.stakingRewards != address(0),
            "Factory notifyRewardAmount: not deployed"
        );
        require(
            info.rewardAmountJONES > 0,
            "Factory notifyRewardAmount: Reward amount must be greater than 0"
        );
        uint256 rewardAmountJONES = 0;
        if (info.rewardAmountJONES > 0) {
            rewardAmountJONES = info.rewardAmountJONES;
            info.rewardAmountJONES = 0;
            require(
                IERC20(rewardsTokenJones).transfer(
                    info.stakingRewards,
                    rewardAmountJONES
                ),
                "Factory notifyRewardAmount: transfer failed"
            );
        }

        StakingRewards(info.stakingRewards).notifyRewardAmount(
            rewardAmountJONES
        );
    }

    /// call notifyRewardAmount for all staking tokens.
    function notifyRewardAmounts() public onlyOwner {
        require(
            stakingID.length > 0,
            "Factory notifyRewardAmounts: called before any deploys"
        );
        for (uint256 i = 0; i < stakingID.length; i++) {
            notifyRewardAmount(stakingID[i]);
        }
    }

    /// add address to whitelist
    /// @param _contract address of contract to be added to the whitelist
    /// @param _id staking ID for the farm
    function addToContractWhitelist(address _contract, uint256 _id)
        external
        onlyOwner
    {
        StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[_id];
        require(
            info.stakingRewards != address(0),
            "Factory: StakingRewards not deployed"
        );
        StakingRewards(info.stakingRewards).addToContractWhitelist(_contract);
    }

    /// remove address from whitelist
    /// @param _contract address of contract to be removed from whitelist
    /// @param _id staking ID for the farm
    function removeFromContractWhitelist(address _contract, uint256 _id)
        external
        onlyOwner
    {
        StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[_id];
        require(
            info.stakingRewards != address(0),
            "Factory: StakingRewards not deployed"
        );
        StakingRewards(info.stakingRewards).removeFromContractWhitelist(
            _contract
        );
    }
}

