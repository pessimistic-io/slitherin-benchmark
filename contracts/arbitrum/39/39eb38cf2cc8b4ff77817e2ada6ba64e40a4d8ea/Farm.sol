pragma solidity 0.8.10;

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@&....(@@@@@@@@@@@@@..../@@@@@@@@@//
//@@@@@@........../@@@@@@@........../@@@@@@//
//@@@@@............(@@@@@............(@@@@@//
//@@@@@(............@@@@@(...........&@@@@@//
//@@@@@@@...........&@@@@@@.........@@@@@@@//
//@@@@@@@@@@@@@@%..../@@@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@...@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@@@......(&@@@@@@@@@@@@//
//@@@@@@#.........@@@@@@#...........@@@@@@@//
//@@@@@/...........%@@@@@............%@@@@@//
//@@@@@............#@@@@@............%@@@@@//
//@@@@@@..........#@@@@@@@/.........#@@@@@@//
//@@@@@@@@@&/.(@@@@@@@@@@@@@@&/.(&@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@//

import "./IERC721Receiver.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import {INonfungiblePositionManager as INFPM, IUniswapV3Factory} from "./UniswapV3.sol";

// Defines the Uniswap pool init data for constructor.
// tokenA - Address of tokenA
// tokenB - Address of tokenB
// feeTier - Fee tier for the Uniswap pool
// tickLowerAllowed - Lower bound of the tick range for farm
// tickUpperAllowed - Upper bound of the tick range for farm
struct UniswapPoolData {
    address tokenA;
    address tokenB;
    uint24 feeTier;
    int24 tickLowerAllowed;
    int24 tickUpperAllowed;
}

// Defines the reward data for constructor.
// token - Address of the token
// tknManager - Authority to update rewardToken related Params.
// emergencyReturn - Address to recover the token to in case of emergency.
// rewardRates - Reward rates for fund types. (max length is 2)
//               Only the first two elements would be considered
struct RewardTokenData {
    address token;
    address tknManager;
    address emergencyReturn;
    uint256[] rewardsPerSec;
}

contract Farm is Ownable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    // Defines the reward funds for the farm
    // totalLiquidity - amount of liquidity sharing the rewards in the fund
    // rewardsPerSec - the emission rate of the fund
    // accRewardPerShare - the accumulated reward per share
    struct RewardFund {
        uint256 totalLiquidity;
        uint256[] rewardsPerSec;
        uint256[] accRewardPerShare;
    }

    // Keeps track of a deposit's share in a reward fund.
    // fund id - id of the subscribed reward fund
    // rewardDebt - rewards claimed for a deposit corresponding to
    //              latest accRewardPerShare value of the budget
    // rewardClaimed - rewards claimed for a deposit from the reward fund
    struct Subscription {
        uint8 fundId;
        uint256[] rewardDebt;
        uint256[] rewardClaimed;
    }

    // Deposit information
    // locked - determines if the deposit is locked or not
    // liquidity - amount of liquidity in the deposit
    // tokenId - maps to uniswap NFT token id
    // startTime - time of deposit
    // expiryDate - expiry time (if deposit is locked)
    // totalRewardsClaimed - total rewards claimed for the deposit
    struct Deposit {
        bool locked;
        uint256 liquidity;
        uint256 tokenId;
        uint256 startTime;
        uint256 expiryDate;
        uint256[] totalRewardsClaimed;
    }

    struct RewardData {
        address tknManager;
        address emergencyReturn;
        uint8 id;
        uint256 accRewards;
        uint256 supply;
    }

    // constants
    address public constant NFPM = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public constant UNIV3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;
    uint8 public constant COMMON_FUND_ID = 0;
    uint8 public constant LOCKUP_FUND_ID = 1;
    uint256 public constant PREC = 1e18;
    uint256 public constant MIN_COOLDOWN_PERIOD = 2 days;
    uint256 public constant MAX_NUM_REWARDS = 2;

    // Global Params
    bool public isPaused;
    bool public inEmergency;

    // UniswapV3 params
    int24 public tickLowerAllowed;
    int24 public tickUpperAllowed;
    address public immutable uniswapPool;

    uint256 public cooldownPeriod;
    uint256 public lastFundUpdateTime;
    uint256 public immutable farmStartTime;

    // Reward info
    RewardFund[] public rewardFunds;
    address[] public rewardTokens;
    mapping(address => RewardData) public rewardData;
    mapping(address => Deposit[]) public deposits;
    mapping(uint256 => Subscription[]) public subscriptions;

    event Deposited(
        address indexed account,
        bool locked,
        uint256 tokenId,
        uint256 liquidity
    );
    event CooldownInitiated(
        address indexed account,
        uint256 tokenId,
        uint256 expiryDate
    );
    event DepositWithdrawn(
        address indexed account,
        uint256 tokenId,
        uint256 startTime,
        uint256 endTime,
        uint256 liquidity,
        uint256[] totalRewardsClaimed
    );
    event RewardsClaimed(
        address indexed account,
        uint8 fundId,
        uint256 tokenId,
        uint256 liquidity,
        uint256 fundLiquidity,
        uint256[] rewardAmount
    );
    event PoolUnsubscribed(
        address indexed account,
        uint8 fundId,
        uint256 depositId,
        uint256 startTime,
        uint256 endTime,
        uint256[] totalRewardsClaimed
    );
    event CooldownPeriodUpdated(
        uint256 oldCooldownPeriod,
        uint256 newCooldownPeriod
    );
    event RewardRateUpdated(
        address rewardToken,
        uint256[] oldRewardRate,
        uint256[] newRewardRate
    );
    event EmergencyClaim(address indexed account);
    event FundsRecovered(
        address indexed account,
        address rwdToken,
        uint256 amount
    );
    event DepositPaused(bool paused);

    modifier notPaused() {
        require(!isPaused, "Farm is paused");
        _;
    }

    modifier notInEmergency() {
        require(!inEmergency, "Emergency, Please withdraw");
        _;
    }

    modifier isTokenManager(address _rwdToken) {
        require(
            msg.sender == rewardData[_rwdToken].tknManager,
            "Not the token manager"
        );
        _;
    }

    /// @notice constructor
    /// @param _farmStartTime - time of farm start
    /// @param _cooldownPeriod - cooldown period for locked deposits
    /// @dev _cooldownPeriod = 0 Disables lockup functionality for the farm.
    /// @param _uniswapPoolData - init data for UniswapV3 pool
    /// @param _rewardData - init data for reward tokens
    constructor(
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        UniswapPoolData memory _uniswapPoolData,
        RewardTokenData[] memory _rewardData
    ) {
        // Initialize farm global params
        lastFundUpdateTime = _farmStartTime;
        farmStartTime = _farmStartTime;
        isPaused = false;
        inEmergency = false;

        // initialize uniswap related data
        tickLowerAllowed = _uniswapPoolData.tickLowerAllowed;
        tickUpperAllowed = _uniswapPoolData.tickUpperAllowed;
        uniswapPool = IUniswapV3Factory(UNIV3_FACTORY).getPool(
            _uniswapPoolData.tokenB,
            _uniswapPoolData.tokenA,
            _uniswapPoolData.feeTier
        );

        // Check for lockup functionality
        // @dev If _cooldownPeriod is 0, then the lockup functionality is disabled for
        // the farm.
        uint8 numFunds = 1;
        if (_cooldownPeriod > 0) {
            require(
                _cooldownPeriod > MIN_COOLDOWN_PERIOD,
                "Cooldown < MinCooldownPeriod"
            );
            cooldownPeriod = _cooldownPeriod;
            numFunds = 2;
        }
        _setupFarm(numFunds, _rewardData);
    }

    /// @notice Function is called when user transfers the NFT to the contract.
    /// @param _from The address of the owner.
    /// @param _tokenId nft Id generated by uniswap v3.
    /// @param _data The data should be the lockup flag (bool).
    function onERC721Received(
        address, // unused variable. not named
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external override notPaused returns (bytes4) {
        require(
            msg.sender == NFPM,
            "UniswapV3Staker::onERC721Received: not a univ3 nft"
        );

        require(_data.length > 0, "UniswapV3Staker::onERC721Received: no data");

        bool lockup = abi.decode(_data, (bool));
        if (cooldownPeriod == 0) {
            require(!lockup, "Lockup functionality is disabled");
        }

        // update the reward funds
        _updateFarmRewardData();

        // Validate the position and get the liquidity
        uint256 liquidity = _getLiquidity(_tokenId);

        // Prepare data to be stored.
        Deposit memory userDeposit = Deposit({
            locked: lockup,
            tokenId: _tokenId,
            startTime: block.timestamp,
            expiryDate: 0,
            totalRewardsClaimed: new uint256[](rewardTokens.length),
            liquidity: liquidity
        });

        // @dev Add the deposit to the user's deposit list
        deposits[_from].push(userDeposit);
        // Add common fund subscription to the user's deposit
        _subscribeRewardFund(COMMON_FUND_ID, _tokenId, liquidity);

        if (lockup) {
            // Add lockup fund subscription to the user's deposit
            _subscribeRewardFund(LOCKUP_FUND_ID, _tokenId, liquidity);
        }

        emit Deposited(_from, lockup, _tokenId, liquidity);
        return this.onERC721Received.selector;
    }

    /// @notice Function to lock a staked deposit
    /// @param _depositId The id of the deposit to be locked
    /// @dev _depositId is corresponding to the user's deposit
    function initiateCooldown(uint256 _depositId)
        external
        notInEmergency
        nonReentrant
    {
        address account = msg.sender;
        _isValidDeposit(account, _depositId);
        Deposit storage userDeposit = deposits[account][_depositId];

        // validate if the deposit is in locked state
        require(userDeposit.locked, "Can not initiate cooldown");

        // update the deposit expiry time & lock status
        userDeposit.expiryDate = block.timestamp + cooldownPeriod;
        userDeposit.locked = false;

        // claim the pending rewards for the user
        _claimRewards(account, _depositId);

        // Unsubscribe the deposit from the lockup reward fund
        _unsubscribeRewardFund(LOCKUP_FUND_ID, account, _depositId);

        emit CooldownInitiated(
            account,
            userDeposit.tokenId,
            userDeposit.expiryDate
        );
    }

    /// @notice Function to withdraw a deposit from the farm.
    /// @param _depositId The id of the deposit to be withdrawn
    function withdraw(uint256 _depositId) external nonReentrant {
        address account = msg.sender;
        _isValidDeposit(account, _depositId);
        Deposit memory userDeposit = deposits[account][_depositId];

        // Check for the withdrawal criteria
        // Note: In case of emergency, skip the cooldown check
        if (!inEmergency) {
            require(!userDeposit.locked, "Please initiate cooldown");
            if (userDeposit.expiryDate > 0) {
                // Cooldown is initiated for the user
                require(
                    userDeposit.expiryDate <= block.timestamp,
                    "Deposit is in cooldown"
                );
            }
        }

        // Compute the user's unclaimed rewards
        _claimRewards(account, _depositId);

        // Store the total rewards earned
        uint256[] memory totalRewards = deposits[account][_depositId]
            .totalRewardsClaimed;

        // unsubscribe the user from the common reward fund
        _unsubscribeRewardFund(COMMON_FUND_ID, account, _depositId);

        // Update the user's deposit list
        deposits[account][_depositId] = deposits[account][
            deposits[account].length - 1
        ];
        deposits[account].pop();

        // Transfer the nft back to the user.
        INFPM(NFPM).safeTransferFrom(
            address(this),
            account,
            userDeposit.tokenId
        );

        emit DepositWithdrawn(
            account,
            userDeposit.tokenId,
            userDeposit.startTime,
            block.timestamp,
            userDeposit.liquidity,
            totalRewards
        );
    }

    /// @notice Claim rewards for the user.
    /// @param _account The user's address
    /// @param _depositId The id of the deposit
    /// @dev Anyone can call this function to claim rewards for the user
    function claimRewards(address _account, uint256 _depositId)
        external
        notInEmergency
        nonReentrant
    {
        _isValidDeposit(_account, _depositId);
        _claimRewards(_account, _depositId);
    }

    /// @notice Claim rewards for the user.
    /// @param _depositId The id of the deposit
    function claimRewards(uint256 _depositId)
        external
        notInEmergency
        nonReentrant
    {
        address account = msg.sender;
        _isValidDeposit(account, _depositId);
        _claimRewards(account, _depositId);
    }

    /// @notice Add rewards to the farm.
    /// @param _rwdToken the reward token's address.
    /// @param _amount the amount of reward tokens to add.
    function addRewards(address _rwdToken, uint256 _amount)
        external
        nonReentrant
    {
        require(
            rewardData[_rwdToken].tknManager != address(0),
            "Invalid reward token"
        );
        _updateFarmRewardData();
        rewardData[_rwdToken].supply += _amount;
        IERC20(_rwdToken).safeTransferFrom(msg.sender, address(this), _amount);
    }

    // --------------------- Admin  Functions ---------------------
    /// @notice Update the cooldown period
    /// @param _newCooldownPeriod The new cooldown period (in seconds)
    function updateCooldownPeriod(uint256 _newCooldownPeriod)
        external
        onlyOwner
    {
        require(cooldownPeriod != 0, "Farm does not support lockup");
        require(
            _newCooldownPeriod > MIN_COOLDOWN_PERIOD,
            "Cooldown period too low"
        );
        uint256 oldCooldownPeriod = cooldownPeriod;
        cooldownPeriod = _newCooldownPeriod;
        emit CooldownPeriodUpdated(oldCooldownPeriod, _newCooldownPeriod);
    }

    /// @notice Pause / UnPause the deposit
    function toggleDepositPause() external onlyOwner {
        isPaused = !isPaused;
        emit DepositPaused(isPaused);
    }

    /// @notice Recover rewardToken from the farm in case of EMERGENCY
    /// @dev Shuts down the farm completely
    function declareEmergency() external onlyOwner nonReentrant {
        _updateFarmRewardData();
        cooldownPeriod = 0;
        isPaused = true;
        inEmergency = true;
        for (uint8 iRwd = 0; iRwd < rewardTokens.length; ++iRwd) {
            _recoverRewardFunds(rewardTokens[iRwd], type(uint256).max);
        }
    }

    // --------------------- Token Manager Functions ---------------------
    /// @notice Get the remaining balance out of the  farm
    /// @param _rwdToken The reward token's address
    /// @param _amount The amount of the reward token to be withdrawn
    /// @dev Function recovers minOf(_amount, rewardsLeft)
    /// @dev In case of partial withdraw of funds, the reward rate has to be set manually again.
    function recoverRewardFunds(address _rwdToken, uint256 _amount)
        external
        isTokenManager(_rwdToken)
        nonReentrant
    {
        _updateFarmRewardData();
        _recoverRewardFunds(_rwdToken, _amount);
    }

    /// @notice Function to update reward params for a fund.
    /// @param _rwdToken The reward token's address
    /// @param _newRewardRates The new reward rate for the fund (includes the precision)
    function setRewardRate(address _rwdToken, uint256[] memory _newRewardRates)
        external
        isTokenManager(_rwdToken)
    {
        _updateFarmRewardData();
        _setRewardRate(_rwdToken, _newRewardRates);
    }

    /// @notice Function to compute the total accrued rewards for a deposit
    /// @param _account The user's address
    /// @param _depositId The id of the deposit
    /// @return rewards The total accrued rewards for the deposit (uint256[])
    function computeRewards(address _account, uint256 _depositId)
        external
        view
        returns (uint256[] memory rewards)
    {
        _isValidDeposit(_account, _depositId);
        Deposit storage userDeposit = deposits[_account][_depositId];
        Subscription[] storage depositSubs = subscriptions[userDeposit.tokenId];
        RewardFund[] memory funds = rewardFunds;
        uint256 numRewards = rewardTokens.length;
        rewards = new uint256[](numRewards);

        uint256 time = 0;
        // In case the reward is not updated
        if (block.timestamp > lastFundUpdateTime) {
            time = block.timestamp - lastFundUpdateTime;
        }

        // Update the two reward funds.
        for (uint8 iSub = 0; iSub < depositSubs.length; ++iSub) {
            uint8 fundId = depositSubs[iSub].fundId;
            for (uint8 iRwd = 0; iRwd < numRewards; ++iRwd) {
                if (funds[fundId].totalLiquidity > 0) {
                    uint256 accRewards = _getAccRewards(iRwd, fundId, time);
                    // update the accRewardPerShare for delta time.
                    funds[fundId].accRewardPerShare[iRwd] +=
                        (accRewards * PREC) /
                        funds[fundId].totalLiquidity;
                }
                rewards[iRwd] +=
                    ((userDeposit.liquidity *
                        funds[fundId].accRewardPerShare[iRwd]) / PREC) -
                    depositSubs[iSub].rewardDebt[iRwd];
            }
        }
        return rewards;
    }

    /// @notice get number of deposits for an account
    /// @param _account The user's address
    function getNumDeposits(address _account) external view returns (uint256) {
        return deposits[_account].length;
    }

    /// @notice get deposit info for an account
    /// @notice _account The user's address
    /// @notice _depositId The id of the deposit
    function getDeposit(address _account, uint256 _depositId)
        external
        view
        returns (Deposit memory)
    {
        return deposits[_account][_depositId];
    }

    /// @notice get number of deposits for an account
    /// @param _tokenId The token's id
    function getNumSubscriptions(uint256 _tokenId)
        external
        view
        returns (uint256)
    {
        return subscriptions[_tokenId].length;
    }

    /// @notice get subscription stats for a deposit.
    /// @param _tokenId The token's id
    /// @param _subscriptionId The subscription's id
    function getSubscriptionInfo(uint256 _tokenId, uint256 _subscriptionId)
        external
        view
        returns (Subscription memory)
    {
        require(
            _subscriptionId < subscriptions[_tokenId].length,
            "Subscription does not exist"
        );
        return subscriptions[_tokenId][_subscriptionId];
    }

    /// @notice get reward rates for a rewardToken.
    /// @param _rwdToken The reward token's address
    /// @return The reward rates for the reward token (uint256[])
    function getRewardRates(address _rwdToken)
        external
        view
        returns (uint256[] memory)
    {
        uint256 numFunds = rewardFunds.length;
        uint256[] memory rates = new uint256[](numFunds);
        uint8 id = rewardData[_rwdToken].id;
        for (uint8 iFund = 0; iFund < numFunds; ++iFund) {
            rates[iFund] = rewardFunds[iFund].rewardsPerSec[id];
        }
        return rates;
    }

    /// @notice get farm reward fund info.
    /// @param _fundId The fund's id
    function getRewardFundInfo(uint8 _fundId)
        external
        view
        returns (RewardFund memory)
    {
        return rewardFunds[_fundId];
    }

    /// @notice Get the remaining reward balance for the farm.
    /// @param _rwdToken The reward token's address
    function getRewardBalance(address _rwdToken) public view returns (uint256) {
        uint256 rwdId = rewardData[_rwdToken].id;
        require(rewardTokens[rwdId] == _rwdToken, "Invalid _rwdToken");

        uint256 numFunds = rewardFunds.length;
        uint256 rewardsAcc = rewardData[_rwdToken].accRewards;
        uint256 supply = rewardData[_rwdToken].supply;
        if (block.timestamp > lastFundUpdateTime) {
            uint256 time = block.timestamp - lastFundUpdateTime;
            for (uint8 iFund = 0; iFund < numFunds; ++iFund) {
                if (rewardFunds[iFund].totalLiquidity > 0) {
                    rewardsAcc +=
                        rewardFunds[iFund].rewardsPerSec[rwdId] *
                        time;
                }
            }
        }
        if (rewardsAcc >= supply) {
            return 0;
        }
        return (supply - rewardsAcc);
    }

    /// @notice Claim rewards for the user.
    /// @param _account The user's address
    /// @param _depositId The id of the deposit
    /// @dev NOTE: any function calling this private
    ///     function should be marked as non-reentrant
    function _claimRewards(address _account, uint256 _depositId) private {
        _updateFarmRewardData();

        Deposit storage userDeposit = deposits[_account][_depositId];
        Subscription[] storage depositSubs = subscriptions[userDeposit.tokenId];

        uint256 numRewards = rewardTokens.length;
        uint256 numSubs = depositSubs.length;
        uint256[] memory totalRewards = new uint256[](numRewards);
        // Compute the rewards for each subscription.
        for (uint8 iSub = 0; iSub < numSubs; ++iSub) {
            uint8 fundId = depositSubs[iSub].fundId;
            uint256[] memory rewards = new uint256[](numRewards);
            for (uint256 iRwd = 0; iRwd < numRewards; ++iRwd) {
                // rewards = (liquidity * accRewardPerShare) / PREC - rewardDebt
                uint256 accRewards = (userDeposit.liquidity *
                    rewardFunds[fundId].accRewardPerShare[iRwd]) / PREC;
                rewards[iRwd] = accRewards - depositSubs[iSub].rewardDebt[iRwd];
                depositSubs[iSub].rewardClaimed[iRwd] += rewards[iRwd];
                totalRewards[iRwd] += rewards[iRwd];

                // Update userRewardDebt for the subscriptions
                // rewardDebt = liquidity * accRewardPerShare
                depositSubs[iSub].rewardDebt[iRwd] = accRewards;
            }

            emit RewardsClaimed(
                _account,
                fundId,
                userDeposit.tokenId,
                userDeposit.liquidity,
                rewardFunds[fundId].totalLiquidity,
                rewards
            );
        }

        for (uint8 iRwd = 0; iRwd < numRewards; ++iRwd) {
            if (totalRewards[iRwd] > 0) {
                // Update the total rewards earned for the deposit
                userDeposit.totalRewardsClaimed[iRwd] += totalRewards[iRwd];
                IERC20(rewardTokens[iRwd]).safeTransfer(
                    _account,
                    totalRewards[iRwd]
                );
            }
        }
    }

    /// @notice Get the remaining balance out of the  farm
    /// @param _rwdToken The reward token's address
    /// @param _amount The amount of the reward token to be withdrawn
    /// @dev Function recovers minOf(_amount, rewardsLeft)
    /// @dev In case of partial withdraw of funds, the reward rate has to be set manually again.
    function _recoverRewardFunds(address _rwdToken, uint256 _amount) private {
        address emergencyRet = rewardData[_rwdToken].emergencyReturn;
        uint256 rewardsLeft = getRewardBalance(_rwdToken);
        uint256 amountToRecover = _amount;
        if (_amount >= rewardsLeft) {
            amountToRecover = rewardsLeft;
            _setRewardRate(_rwdToken, new uint256[](rewardFunds.length));
        }
        if (amountToRecover > 0) {
            rewardData[_rwdToken].supply -= amountToRecover;
            IERC20(_rwdToken).safeTransfer(emergencyRet, amountToRecover);
            emit FundsRecovered(emergencyRet, _rwdToken, amountToRecover);
        }
    }

    /// @notice Function to update reward params for a fund.
    /// @param _rwdToken The reward token's address
    /// @param _newRewardRates The new reward rate for the fund (includes the precision)
    function _setRewardRate(address _rwdToken, uint256[] memory _newRewardRates)
        private
    {
        uint8 id = rewardData[_rwdToken].id;
        uint256 numFunds = rewardFunds.length;
        require(
            _newRewardRates.length == numFunds,
            "Invalid reward rates length"
        );
        uint256[] memory oldRewardRates = new uint256[](numFunds);
        // Update the reward rate
        for (uint8 iFund = 0; iFund < numFunds; ++iFund) {
            oldRewardRates[iFund] = rewardFunds[iFund].rewardsPerSec[id];
            rewardFunds[iFund].rewardsPerSec[id] = _newRewardRates[iFund];
        }
        emit RewardRateUpdated(_rwdToken, oldRewardRates, _newRewardRates);
    }

    /// @notice Add subscription to the reward fund for a deposit
    /// @param _tokenId The tokenId of the deposit
    /// @param _fundId The reward fund id
    /// @param _liquidity The liquidity of the deposit
    function _subscribeRewardFund(
        uint8 _fundId,
        uint256 _tokenId,
        uint256 _liquidity
    ) private {
        require(_fundId < rewardFunds.length, "Invalid fund id");
        // Subscribe to the reward fund
        uint256 numRewards = rewardTokens.length;
        subscriptions[_tokenId].push(
            Subscription({
                fundId: _fundId,
                rewardDebt: new uint256[](numRewards),
                rewardClaimed: new uint256[](numRewards)
            })
        );
        uint256 subId = subscriptions[_tokenId].length - 1;

        // initialize user's reward debt
        for (uint8 iRwd = 0; iRwd < numRewards; ++iRwd) {
            subscriptions[_tokenId][subId].rewardDebt[iRwd] =
                (_liquidity * rewardFunds[_fundId].accRewardPerShare[iRwd]) /
                PREC;
        }
        // Update the totalLiquidity for the fund
        rewardFunds[_fundId].totalLiquidity += _liquidity;
    }

    /// @notice Unsubscribe a reward fund from a deposit
    /// @param _fundId The reward fund id
    /// @param _account The user's address
    /// @param _depositId The deposit id corresponding to the user
    /// @dev The rewards claimed from the reward fund is persisted in the event
    function _unsubscribeRewardFund(
        uint8 _fundId,
        address _account,
        uint256 _depositId
    ) private {
        require(_fundId < rewardFunds.length, "Invalid fund id");
        Deposit storage userDeposit = deposits[_account][_depositId];
        uint256 numRewards = rewardTokens.length;

        // Unsubscribe from the reward fund
        Subscription[] storage depositSubs = subscriptions[userDeposit.tokenId];
        uint256 numSubs = depositSubs.length;
        for (uint256 iSub = 0; iSub < numSubs; ++iSub) {
            if (depositSubs[iSub].fundId == _fundId) {
                // Persist the reward information
                uint256[] memory rewardClaimed = new uint256[](numRewards);

                for (uint8 iRwd = 0; iRwd < numRewards; ++iRwd) {
                    rewardClaimed[iRwd] = depositSubs[iSub].rewardClaimed[iRwd];
                }

                // Delete the subscription from the list
                depositSubs[iSub] = depositSubs[numSubs - 1];
                depositSubs.pop();

                // Remove the liquidity from the reward fund
                rewardFunds[_fundId].totalLiquidity -= userDeposit.liquidity;

                emit PoolUnsubscribed(
                    _account,
                    _fundId,
                    userDeposit.tokenId,
                    userDeposit.startTime,
                    block.timestamp,
                    rewardClaimed
                );

                break;
            }
        }
    }

    /// @notice Function to update the FarmRewardData for all funds
    function _updateFarmRewardData() private {
        if (block.timestamp > lastFundUpdateTime) {
            uint256 time = block.timestamp - lastFundUpdateTime;
            uint256 numRewards = rewardTokens.length;
            // Update the reward funds.
            for (uint8 iFund = 0; iFund < rewardFunds.length; ++iFund) {
                RewardFund memory fund = rewardFunds[iFund];
                if (fund.totalLiquidity > 0) {
                    for (uint8 iRwd = 0; iRwd < numRewards; ++iRwd) {
                        uint256 accRewards = _getAccRewards(iRwd, iFund, time);
                        rewardData[rewardTokens[iRwd]].accRewards += accRewards;
                        fund.accRewardPerShare[iRwd] +=
                            (accRewards * PREC) /
                            fund.totalLiquidity;
                    }
                }
                rewardFunds[iFund] = fund;
            }
            lastFundUpdateTime = block.timestamp;
        }
    }

    /// @notice Function to setup the reward funds during construction.
    /// @param _numFunds - Number of reward funds to setup.
    /// @param _rewardData - Reward data for each reward token.
    function _setupFarm(uint8 _numFunds, RewardTokenData[] memory _rewardData)
        private
    {
        // Setup reward related information.
        uint256 numRewards = _rewardData.length;
        // @dev Allow only max 2 rewards.
        require(
            numRewards > 0 && numRewards <= MAX_NUM_REWARDS,
            "Invalid reward data"
        );

        // Initialize fund storage
        for (uint8 i = 0; i < _numFunds; ++i) {
            RewardFund memory _rewardFund = RewardFund({
                totalLiquidity: 0,
                rewardsPerSec: new uint256[](numRewards),
                accRewardPerShare: new uint256[](numRewards)
            });
            rewardFunds.push(_rewardFund);
        }

        // Initialize reward Data
        rewardTokens = new address[](numRewards);
        for (uint8 iRwd = 0; iRwd < numRewards; ++iRwd) {
            require(
                _rewardData[iRwd].rewardsPerSec.length == _numFunds,
                "Invalid reward rate data"
            );
            address rwdToken = _rewardData[iRwd].token;
            // Validate if addresses are correct
            _isNonZeroAddr(rwdToken);
            _isNonZeroAddr(_rewardData[iRwd].tknManager);
            _isNonZeroAddr(_rewardData[iRwd].emergencyReturn);
            for (uint8 iFund = 0; iFund < _numFunds; ++iFund) {
                // @dev assign the relevant reward rates to the funds
                rewardFunds[iFund].rewardsPerSec[iRwd] = _rewardData[iRwd]
                    .rewardsPerSec[iFund];
            }
            rewardTokens[iRwd] = rwdToken;
            rewardData[rwdToken] = RewardData({
                id: iRwd,
                tknManager: _rewardData[iRwd].tknManager,
                emergencyReturn: _rewardData[iRwd].emergencyReturn,
                accRewards: 0,
                supply: 0
            });
        }
    }

    function _getAccRewards(
        uint8 _rwdId,
        uint8 _fundId,
        uint256 _time
    ) private view returns (uint256) {
        RewardFund memory fund = rewardFunds[_fundId];
        address rwdToken = rewardTokens[_rwdId];
        uint256 rwdSupply = rewardData[rwdToken].supply;
        uint256 rwdAccrued = rewardData[rwdToken].accRewards;

        uint256 rwdBal = 0;
        if (rwdSupply > rwdAccrued) {
            rwdBal = rwdSupply - rwdAccrued;
        }
        uint256 accRewards = fund.rewardsPerSec[_rwdId] * _time;
        if (accRewards > rwdBal) {
            accRewards = rwdBal;
        }
        return accRewards;
    }

    /// @notice Validate the position for the pool and get Liquidity
    /// @param _tokenId The tokenId of the position
    /// @dev the position must adhere to the price ranges
    /// @dev Only allow specific pool token to be staked.
    function _getLiquidity(uint256 _tokenId) private view returns (uint256) {
        /// @dev Get the info of the required token
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = INFPM(NFPM).positions(_tokenId);

        /// @dev Check if the token belongs to correct pool
        require(
            uniswapPool ==
                IUniswapV3Factory(UNIV3_FACTORY).getPool(token0, token1, fee),
            "Incorrect pool token"
        );

        /// @dev Check if the token adheres to the tick range
        require(
            tickLower == tickLowerAllowed && tickUpper == tickUpperAllowed,
            "Incorrect tick range"
        );

        return uint256(liquidity);
    }

    /// @notice Validate the deposit for account
    function _isValidDeposit(address _account, uint256 _depositId)
        private
        view
    {
        require(
            _depositId < deposits[_account].length,
            "Deposit does not exist"
        );
    }

    /// @notice Validate address
    function _isNonZeroAddr(address _addr) private pure {
        require(_addr != address(0), "Invalid address");
    }
}

