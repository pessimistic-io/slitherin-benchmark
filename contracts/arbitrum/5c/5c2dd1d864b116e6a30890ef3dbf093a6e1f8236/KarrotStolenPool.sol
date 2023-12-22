//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
                    ____     ____
                  /'    |   |    \
                /    /  |   | \   \
              /    / |  |   |  \   \
             (   /   |  """"   |\   \       
             | /   / /^\    /^\  \  _|           
              ~   | |   |  |   | | ~
                  | |__O|__|O__| |
                /~~      \/     ~~\
               /   (      |      )  \
         _--_  /,   \____/^\___/'   \  _--_
       /~    ~\ / -____-|_|_|-____-\ /~    ~\
     /________|___/~~~~\___/~~~~\ __|________\
--~~~          ^ |     |   |     |  -     :  ~~~~~:~-_     ___-----~~~~~~~~|
   /             `^-^-^'   `^-^-^'                  :  ~\ /'   ____/--------|
       --                                            ;   |/~~~------~~~~~~~~~|
 ;                                    :              :    |----------/--------|
:                     ,                           ;    .  |---\\--------------|
 :     -                          .                  : : |______________-__|
  :              ,                 ,                :   /'~----___________|
__  \\\        ^                          ,, ;; ;; ;._-~
  ~~~-----____________________________________----~~~


     _______.___________.  ______    __       _______ .__   __. .______     ______     ______    __      
    /       |           | /  __  \  |  |     |   ____||  \ |  | |   _  \   /  __  \   /  __  \  |  |     
   |   (----`---|  |----`|  |  |  | |  |     |  |__   |   \|  | |  |_)  | |  |  |  | |  |  |  | |  |     
    \   \       |  |     |  |  |  | |  |     |   __|  |  . `  | |   ___/  |  |  |  | |  |  |  | |  |     
.----)   |      |  |     |  `--'  | |  `----.|  |____ |  |\   | |  |      |  `--'  | |  `--'  | |  `----.
|_______/       |__|      \______/  |_______||_______||__| \__| | _|       \______/   \______/  |_______|
                                                                                                         

 */

import "./IERC20.sol";
import "./AccessControl.sol";
import "./Math.sol";
import "./ReentrancyGuard.sol";
import "./KarrotInterfaces.sol";

/**
StolenPool: where the stolen karrots go
- claim tax (rabbits stealing karrots) from karrotChef are deposited here
- every deposit is grouped into an epoch (1 day) based on time of deposit
- rabbit attacks during this epoch are weighted by tier and stake claim to a portion of the epoch's deposited karrots
- epoch ends, rewards are calculated, and rewards are claimable by attackers based on tier and number of successful attacks during that epoch
- rewards are claimable only for previous epochs (not current)
 */
 
contract KarrotStolenPool is AccessControl, ReentrancyGuard {
    
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    IAttackRewardCalculator public rewardCalculator;
    IConfig public config;

    address public outputAddress;
    bool public poolOpenTimestampSet;
    bool public stolenPoolAttackIsOpen = false;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    uint16 public constant PERCENTAGE_DENOMINATOR = 10000;
    uint16 public attackBurnPercentage = 1000; //10%
    uint16 public rabbitTier1AttackRewardsWeight = 10000; //1x
    uint16 public rabbitTier2AttackRewardsWeight = 25000; //2.5x
    uint16 public rabbitTier3AttackRewardsWeight = 50000; //5x

    uint32 public poolOpenTimestamp;
    uint32 public stolenPoolEpochLength = 1 days; //1 day
    uint32 public totalAttacks;

    uint256 public totalClaimedRewardsForAll;
    uint256 public totalBurned;
    uint256 public totalMinted;

    mapping(uint256 => uint256) public epochBalances;
    mapping(address => Attack[]) public userAttacks;
    mapping(uint256 => EpochAttackStats) public epochAttackStats;
    mapping(address => UserAttackStats) public userAttackStats;

    struct UserAttackStats {
        uint32 successfulAtacks;
        uint32 lastClaimEpoch;
        uint192 totalClaimedRewards;
    }

    struct EpochAttackStats {
        uint32 tier1;
        uint32 tier2;
        uint32 tier3;
        uint160 total;
    }

    struct Attack {
        uint216 epoch; //takes into account calcs for reward per attack by tier for this epoch (range of timestamps)
        uint32 rabbitId;
        uint8 tier;
        address user;
    }

    event AttackEvent(address indexed sender, uint256 tier);
    event StolenPoolRewardClaimed(address indexed sender, uint256 amount);

    error InvalidCaller(address caller, address expected);
    error CallerIsNotConfig();
    error ForwardFailed();
    error NoRewardsToClaim();
    error PoolOpenTimestampNotSet();
    error PoolOpenTimestampAlreadySet();
    error FirstEpochHasNotPassedYet(uint256 remainingTimeUntilFirstEpochPasses);
    error InvalidRabbitTier();
    error AlreadyClaimedCurrentEpoch();

    constructor(address _configAddress) {
        config = IConfig(_configAddress);
        rewardCalculator = IAttackRewardCalculator(config.attackRewardCalculatorAddress());
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    modifier attackIsOpen() {
        require(stolenPoolAttackIsOpen, "Attack is not open");
        _;
    }

    modifier onlyConfig() {
        if (msg.sender != address(config)) {
            revert CallerIsNotConfig();
        }
        _;
    }

    function deposit(uint256 _amount) external {
        //caller must be KarrotChef contract or admin to add funds
        address karrotChefAddress = config.karrotChefAddress();
        if (msg.sender != karrotChefAddress && !hasRole(ADMIN_ROLE, msg.sender)) {
            revert InvalidCaller(msg.sender, karrotChefAddress);
        }

        //add to this epoch's balance
        uint256 currentEpoch = getCurrentEpoch();
        epochBalances[currentEpoch] += _amount;
        totalBurned += _amount;

        //'burn' input tokens
        IKarrotsToken(config.karrotsAddress()).transferFrom(msg.sender, DEAD_ADDRESS, _amount);

    }

    // [!] check logik - make sure cooldown is controlled from the rabbit contract
    function attack(address _sender, uint256 _rabbitTier, uint256 _rabbitId) external attackIsOpen {
        //caller must be Rabbit contract
        address rabbitAddress = config.rabbitAddress();
        if (msg.sender != rabbitAddress) {
            revert InvalidCaller(msg.sender, rabbitAddress);
        }

        uint256 currentEpoch = getCurrentEpoch();

        //update overall attack stats for this epoch
        if (_rabbitTier == 1) {
            ++epochAttackStats[currentEpoch].tier1;
        } else if (_rabbitTier == 2) {
            ++epochAttackStats[currentEpoch].tier2;
        } else if (_rabbitTier == 3) {
            ++epochAttackStats[currentEpoch].tier3;
        } else {
            revert InvalidRabbitTier();
        }

        ++epochAttackStats[currentEpoch].total;
        ++totalAttacks;

        //set successful attacks for this rabbit id/user and tier and epoch
        userAttacks[_sender].push(Attack(uint216(currentEpoch), uint32(_rabbitId), uint8(_rabbitTier), _sender));
        ++userAttackStats[_sender].successfulAtacks;
        emit AttackEvent(_sender, _rabbitTier);
    }

    function claimRewards() external nonReentrant {

        if(userAttackStats[msg.sender].lastClaimEpoch == uint32(getCurrentEpoch())) {
            revert AlreadyClaimedCurrentEpoch();
        }

        uint256 totalRewardsForUser = getPretaxPendingRewards(msg.sender);

        if (totalRewardsForUser == 0) {
            revert NoRewardsToClaim();
        }

        uint256 burnAmount = Math.mulDiv(
            totalRewardsForUser,
            attackBurnPercentage,
            PERCENTAGE_DENOMINATOR
        );
        
        //update last claim epoch to current epoch to prevent double claiming
        userAttackStats[msg.sender].lastClaimEpoch = uint32(getCurrentEpoch());
        userAttackStats[msg.sender].totalClaimedRewards += uint192(totalRewardsForUser - burnAmount);
        totalClaimedRewardsForAll += totalRewardsForUser - burnAmount;        
        
        // send remaining rewards to user
        totalMinted += totalRewardsForUser - burnAmount;
        IKarrotsToken(config.karrotsAddress()).mint(msg.sender, totalRewardsForUser - burnAmount);

        emit StolenPoolRewardClaimed(msg.sender, totalRewardsForUser - burnAmount);
    }

    function getCurrentEpoch() public view returns (uint256) {
        return Math.mulDiv(
            block.timestamp - poolOpenTimestamp,
            1,
            stolenPoolEpochLength
        );
    }

    // [!] burn pool tokens from empty epochs or claim to treasury if desired, otherwise, leaving them is like burning...
    function transferExtraToTreasury() external onlyRole(ADMIN_ROLE) {
        //add amounts from any epochs without claims to claimable balance, set those epoch balances to 0
        uint256 claimableBalance;
        uint256 currentEpoch = getCurrentEpoch();
        for (uint256 i = 0; i < currentEpoch; i++) {
            if(epochAttackStats[i].total == 0){
                claimableBalance += epochBalances[i];
                epochBalances[i] = 0;    
            }
        }

        IKarrotsToken(config.karrotsAddress()).mint(config.treasuryBAddress(), claimableBalance);
    }

    function getEpochLength() public view returns (uint256) {
        return stolenPoolEpochLength;
    }

    //get seconds until next epoch, with handling for 0th epoch / just starting the pool
    function getSecondsUntilNextEpoch() public view returns (uint256) {
        return stolenPoolEpochLength - ((block.timestamp - poolOpenTimestamp) % stolenPoolEpochLength);
    }

    function getCurrentEpochBalance() public view returns (uint256) {
        uint256 currentEpoch = getCurrentEpoch();
        return epochBalances[currentEpoch];
    }

    function getEpochBalance(uint256 _epoch) public view returns (uint256) {
        return epochBalances[_epoch];
    }

    function getUserAttackEpochs(address _user) public view returns (uint256[] memory) {
        uint256[] memory epochs = new uint256[](userAttacks[_user].length);
        for (uint256 i = 0; i < userAttacks[_user].length; ++i) {
            epochs[i] = userAttacks[_user][i].epoch;
        }
        return epochs;
    }

    /**
        @dev calculate user rewards by summing up rewards from each epoch
        rewards from each epoch are calculated as: baseReward = (total karrots deposited this epoch) / (total successful attacks this epoch)
        where baseReward is scaled based on tier of rabbit attacked such that the relative earnings are: tier 1 = 1x, tier 2 = 2x, tier 3 = 5x
        and 95% of the baseReward is given to the user and 5% is sent to treasury B
     */
    function getPretaxPendingRewards(address _user) public view returns (uint256) {
        //claim rewards from lastClaimEpoch[_user] to currentEpoch
        uint256 currentEpoch = getCurrentEpoch();
        uint256 lastClaimedEpoch = userAttackStats[_user].lastClaimEpoch;

        uint256 totalRewardsForUser;
        for (uint256 i = lastClaimedEpoch; i < currentEpoch; ++i) {
            //get total deposited karrots this epoch
            
            if(epochBalances[i] == 0) {
                continue;
            }

            (uint256 tier1RewardsPerAttack, uint256 tier2RewardsPerAttack, uint256 tier3RewardsPerAttack) = getPretaxPendingRewardsForEpoch(i);

            //now that I have the rewards per attack for each tier, I can calculate the total rewards for the user
            uint256 totalRewardCurrentEpoch = 0;
            for (uint256 j = 0; j < userAttacks[_user].length; ++j) {
                Attack memory thisAttack = userAttacks[_user][j];
                if (thisAttack.epoch == i) {
                    if (thisAttack.tier == 1) {
                        totalRewardCurrentEpoch += tier1RewardsPerAttack;
                    } else if (thisAttack.tier == 2) {
                        totalRewardCurrentEpoch += tier2RewardsPerAttack;
                    } else if (thisAttack.tier == 3) {
                        totalRewardCurrentEpoch += tier3RewardsPerAttack;
                    }
                }
            }

            totalRewardsForUser += totalRewardCurrentEpoch;
        }

        return totalRewardsForUser;
    }

    function getPretaxPendingRewardsForEpoch(uint256 _epoch) public view returns (uint256, uint256, uint256) {
        //get total deposited karrots this epoch
        uint256 totalKarrotsDepositedCurrentEpoch = epochBalances[_epoch];
        EpochAttackStats memory currentEpochStats = epochAttackStats[_epoch];
        uint256 tier1Attacks = currentEpochStats.tier1;
        uint256 tier2Attacks = currentEpochStats.tier2;
        uint256 tier3Attacks = currentEpochStats.tier3;

        //get rewards per attack for each tier [tier1, tier2, tier3]
        uint256[] memory rewardsPerAttackByTier = rewardCalculator.calculateRewardPerAttackByTier(
            tier1Attacks,
            tier2Attacks,
            tier3Attacks,
            rabbitTier1AttackRewardsWeight,
            rabbitTier2AttackRewardsWeight,
            rabbitTier3AttackRewardsWeight,
            totalKarrotsDepositedCurrentEpoch
        );

        return (rewardsPerAttackByTier[0], rewardsPerAttackByTier[1], rewardsPerAttackByTier[2]);
    }

    function getPosttaxPendingRewards(address _user) public view returns (uint256) {
        uint256 pretaxRewards = getPretaxPendingRewards(_user);
        uint256 posttaxRewards = Math.mulDiv(
            pretaxRewards,
            PERCENTAGE_DENOMINATOR - attackBurnPercentage,
            PERCENTAGE_DENOMINATOR
        );
        return posttaxRewards;
    }

    function getUserSuccessfulAttacks(address _user) public view returns (uint32) {
        return userAttackStats[_user].successfulAtacks;
    }

    function getUserLastClaimEpoch(address _user) public view returns (uint32) {
        return userAttackStats[_user].lastClaimEpoch;
    }

    function getUserTotalClaimedRewards(address _user) public view returns (uint192) {
        return userAttackStats[_user].totalClaimedRewards;
    }

    function getEpochTier1Attacks(uint256 _epoch) public view returns (uint32) {
        return epochAttackStats[_epoch].tier1;
    }

    function getEpochTier2Attacks(uint256 _epoch) public view returns (uint32) {
        return epochAttackStats[_epoch].tier2;
    }

    function getEpochTier3Attacks(uint256 _epoch) public view returns (uint32) {
        return epochAttackStats[_epoch].tier3;
    }

    function getEpochTotalAttacks(uint256 _epoch) public view returns (uint160) {
        return epochAttackStats[_epoch].total;
    }

    //=========================================================================
    // SETTERS/WITHDRAWALS
    //=========================================================================

    //corresponds to the call of karrotChef.openKarrotChefDeposits()
    function setStolenPoolOpenTimestamp() external onlyConfig {
        if (!poolOpenTimestampSet) {
            //set timestamp for the start of epochs
            poolOpenTimestamp = uint32(block.timestamp);
            poolOpenTimestampSet = true;
        } else {
            revert PoolOpenTimestampAlreadySet();
        }
    }

    function setStolenPoolAttackIsOpen(bool _isOpen) external onlyConfig {
        if (!poolOpenTimestampSet) {
            revert PoolOpenTimestampNotSet();
        }
        if (poolOpenTimestamp + stolenPoolEpochLength > block.timestamp) {
            revert FirstEpochHasNotPassedYet(block.timestamp - (poolOpenTimestamp + stolenPoolEpochLength));
        }
        stolenPoolAttackIsOpen = _isOpen;
    }

    function setAttackBurnPercentage(uint16 _percentage) external onlyConfig {
        attackBurnPercentage = _percentage;
    }

    function setStolenPoolEpochLength(uint32 _epochLength) external onlyConfig {
        stolenPoolEpochLength = _epochLength;
    }

    //-------------------------------------------------------------------------

    function setConfigManagerAddress(address _configManagerAddress) external onlyRole(ADMIN_ROLE) {
        config = IConfig(_configManagerAddress);
    }

    function setOutputAddress(address _outputAddress) external onlyRole(ADMIN_ROLE) {
        outputAddress = _outputAddress;
    }

    function withdrawERC20FromContract(address _to, address _token) external onlyRole(ADMIN_ROLE) {
        bool os = IERC20(_token).transfer(_to, IERC20(_token).balanceOf(address(this)));
        if (!os) {
            revert ForwardFailed();
        }
    }

    function withdrawEthFromContract() external onlyRole(ADMIN_ROLE) {
        require(outputAddress != address(0), "Payment splitter address not set");
        (bool os, ) = payable(outputAddress).call{value: address(this).balance}("");
        if (!os) {
            revert ForwardFailed();
        }
    }
}

