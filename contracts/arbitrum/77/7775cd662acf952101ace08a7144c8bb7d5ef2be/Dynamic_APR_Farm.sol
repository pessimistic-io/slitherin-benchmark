pragma solidity 0.8.7;

import "./IERC721Receiver.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import {INonfungiblePositionManager as INFPM, IUniswapV3Factory} from "./UniswapV3.sol";

contract Dynamic_APR_Farm is Ownable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    // Defines the reward funds for the farm
    // totalLiquidity - amount of liquidity sharing the rewards in the fund
    // rewardsPerSec - the emision rate of the fund
    // accRewardPerShare - the accumulated reward per share
    struct RewardFund {
        uint256 totalLiquidity;
        uint256 rewardsPerSec;
        uint256 accRewardPerShare;
    }

    // Keeps track of a deposit's share in a reward fund.
    // fund id - id of the subscribed reward fund
    // rewardDebt - rewards claimed for a deposit corresponding to
    //              latest accRewardPerShare value of the budget
    // rewardCalimed - rewards claimed for a deposit from the reward fund
    struct Subscription {
        uint8 fundId;
        uint256 rewardDebt;
        uint256 rewardClaimed;
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
        uint256 totalRewardsClaimed;
    }

    int24 public tickLowerAllowed;
    int24 public tickUpperAllowed;
    bool public isPaused;
    bool public inEmergency;

    address public constant NFPM = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public constant UNIV3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address public immutable uniswapPool;
    address public immutable rewardToken;

    // Emergency address
    address public immutable emergencyReturn;
    uint256 public cooldownPeriod;

    /// Reward settings
    RewardFund[] public rewardFunds;
    uint256 public lastFundUpdateTime;
    uint256 public constant PREC = 1e18;
    uint8 public constant COMMON_FUND_ID = 0;
    uint8 public constant LOCKUP_FUND_ID = 1;

    // Keep track of user deposits
    mapping(address => Deposit[]) public deposits;

    // Keep track of reward subscriptions for each
    // @dev A deposit can subscribe to at max 2 reward funds
    // Deposit subscribes to common reward fund by default.
    // Deposit subscribes to lockup reward fund only if user locks the deposit.
    // The key is the tokenId.
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
        uint256 totalRewardsClaimed
    );
    event RewardRateUpdated(
        uint8 fundId,
        uint256 oldRewardRate,
        uint256 newRewardRate
    );
    event CooldownPeriodUpdated(
        uint256 oldCooldownPeriod,
        uint256 newCooldownPeriod
    );

    event RewardsClaimed(
        address indexed account,
        uint8 fundId,
        uint256 tokenId,
        uint256 liquidity,
        uint256 fundLiquidity,
        uint256 rewardAmount
    );

    event FundsRecovered(address indexed account, uint256 amount);
    event DepositPaused(bool paused);
    event EmergencyClaim(address indexed account);
    event PoolUnsubscribed(
        address indexed account,
        uint256 depositId,
        uint8 fundId,
        uint256 startTime,
        uint256 endTime,
        uint256 totalRewardsClaimed
    );

    modifier notPaused() {
        require(!isPaused, "Farm is paused");
        _;
    }

    modifier notInEmergency() {
        require(!inEmergency, "Emergency, Please withdraw");
        _;
    }

    /// @dev The _nolockupRewardsPerSec, _lockuprewardsPerSec
    ///     includes the precision.
    constructor(
        address _rewardToken,
        address _tokenA,
        address _tokenB,
        address _emergencyReturn,
        int24 _tickLowerAllowed,
        int24 _tickUpperAllowed,
        uint24 _feeTier,
        uint256 _nolockupRewardsPerSec,
        uint256 _lockuprewardsPerSec
    ) public {
        rewardToken = _rewardToken;
        tickLowerAllowed = _tickLowerAllowed;
        tickUpperAllowed = _tickUpperAllowed;
        cooldownPeriod = 21 days;
        emergencyReturn = _emergencyReturn;
        uniswapPool = IUniswapV3Factory(UNIV3_FACTORY).getPool(
            _tokenB,
            _tokenA,
            _feeTier
        );

        /// Setup common reward fund
        rewardFunds.push(
            RewardFund({
                totalLiquidity: 0,
                rewardsPerSec: _nolockupRewardsPerSec,
                accRewardPerShare: 0
            })
        );

        /// Setup lockup reward fund
        rewardFunds.push(
            RewardFund({
                totalLiquidity: 0,
                rewardsPerSec: _lockuprewardsPerSec,
                accRewardPerShare: 0
            })
        );

        lastFundUpdateTime = block.timestamp;
    }

    /// @notice Function is called when user transfers the NFT to the contract.
    /// @param from The address of the owner.
    /// @param tokenId nft Id generated by uniswap v3.
    /// @param data The data should be the lockup flag (bool).
    function onERC721Received(
        address, // unused variable. not named
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override notPaused returns (bytes4) {
        require(
            _msgSender() == NFPM,
            "UniswapV3Staker::onERC721Received: not a univ3 nft"
        );

        require(data.length > 0, "UniswapV3Staker::onERC721Received: no data");

        bool lockup = abi.decode(data, (bool));

        // update the reward funds
        _updateFarmRewardData();

        // Validate the position and get the liquidity
        uint256 liquidity = _getLiquidity(tokenId);

        // Prepare data to be stored.
        Deposit memory userDeposit = Deposit({
            locked: lockup,
            tokenId: tokenId,
            startTime: block.timestamp,
            expiryDate: 0,
            totalRewardsClaimed: 0,
            liquidity: liquidity
        });

        // @dev Add the deposit to the user's deposit list
        deposits[from].push(userDeposit);
        // Add common fund subscription to the user's deposit
        _subscribeRewardFund(COMMON_FUND_ID, userDeposit.tokenId, liquidity);

        if (lockup) {
            // Add lockup fund subscription to the user's deposit
            _subscribeRewardFund(
                LOCKUP_FUND_ID,
                userDeposit.tokenId,
                liquidity
            );
        }

        emit Deposited(from, lockup, tokenId, liquidity);
        return this.onERC721Received.selector;
    }

    /// @notice Function to lock a staked deposit
    /// @param depositId The id of the deposit to be locked
    /// @dev depositId is corresponding to the user's deposit
    function initiateCooldown(uint256 depositId)
        external
        notInEmergency
        nonReentrant
    {
        address account = _msgSender();
        require(deposits[account].length > depositId, "Deposit does not exist");
        Deposit storage userDeposit = deposits[account][depositId];

        // validate if the deposit is in locked state
        require(userDeposit.locked, "Can not initiate cooldown");

        // update the deposit expiry time & lock status
        userDeposit.expiryDate = block.timestamp + cooldownPeriod;
        userDeposit.locked = false;

        // claim the pending rewards for the user
        _claimRewards(account, depositId);

        // Unsubscribe the deposit from the lockup reward fund
        _unsubscribeRewardFund(LOCKUP_FUND_ID, account, depositId);

        emit CooldownInitiated(
            account,
            userDeposit.tokenId,
            userDeposit.expiryDate
        );
    }

    /// @notice Function to withdraw a deposit from the farm.
    /// @param depositId The id of the deposit to be withdrawn
    function withdraw(uint256 depositId) external nonReentrant {
        address account = _msgSender();
        require(deposits[account].length > depositId, "Deposit does not exist");
        Deposit memory userDeposit = deposits[account][depositId];

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
        _claimRewards(account, depositId);

        // Store the total rewards earned
        uint256 totalRewards = deposits[account][depositId].totalRewardsClaimed;

        // unsubscribe the user from the common reward fund
        _unsubscribeRewardFund(COMMON_FUND_ID, account, depositId);

        // Update the user's deposit list
        deposits[account][depositId] = deposits[account][
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
    /// @param account The user's address
    /// @param depositId The id of the deposit
    /// @dev Anyone can call this function to claim rewards for the user
    function claimRewards(address account, uint256 depositId)
        external
        notInEmergency
        nonReentrant
    {
        require(deposits[account].length > depositId, "Deposit does not exist");
        _claimRewards(account, depositId);
    }

    /// @notice Claim rewards for the user.
    /// @param depositId The id of the deposit
    function claimRewards(uint256 depositId)
        external
        notInEmergency
        nonReentrant
    {
        address account = _msgSender();
        require(deposits[account].length > depositId, "Deposit does not exist");
        _claimRewards(account, depositId);
    }

    /// @notice Function to compute the total accrued rewards for a deposit
    /// @param account The user's address
    /// @param depositId The id of the deposit
    /// @return The total accrued rewards for the deposit (uint256)
    function computeRewards(address account, uint256 depositId)
        external
        view
        returns (uint256)
    {
        require(deposits[account].length > depositId, "Deposit does not exist");
        Deposit storage userDeposit = deposits[account][depositId];
        Subscription[] storage depositSubs = subscriptions[userDeposit.tokenId];
        RewardFund[] memory funds = rewardFunds;
        uint256 numRewards = depositSubs.length;
        uint256 rewards = 0;

        // In case the reward is not updated
        uint256 time = block.timestamp - lastFundUpdateTime;
        // Update the two reward funds.
        for (uint8 i = 0; i < depositSubs.length; ++i) {
            uint8 fundId = depositSubs[i].fundId;
            funds[fundId].accRewardPerShare +=
                (funds[fundId].rewardsPerSec * time * PREC) /
                funds[fundId].totalLiquidity;

            rewards +=
                ((userDeposit.liquidity * funds[fundId].accRewardPerShare) /
                    PREC) -
                depositSubs[i].rewardDebt;
        }
        return rewards;
    }

    /// @notice get number of deposits for an account
    /// @param account The user's address
    function getNumDeposits(address account) external view returns (uint256) {
        return deposits[account].length;
    }

    /// @notice get number of deposits for an account
    /// @param tokenId The token's id
    function getNumSubscriptions(uint256 tokenId)
        external
        view
        returns (uint256)
    {
        return subscriptions[tokenId].length;
    }

    // --------------------- Admin  Functions ---------------------
    /// @notice Recover rewardToken from the farm in case of EMERGENCY
    /// @dev Shuts down the farm completely
    function declareEmergency() public onlyOwner {
        setRewardsPerSec(COMMON_FUND_ID, 0);
        setRewardsPerSec(LOCKUP_FUND_ID, 0);
        updateCooldownPeriod(0);
        toggleDepositPause();
        inEmergency = true;
        uint256 amount = IERC20(rewardToken).balanceOf(address(this));
        IERC20(rewardToken).safeTransfer(emergencyReturn, amount);
        emit FundsRecovered(emergencyReturn, amount);
    }

    /// @notice Function to update reward params for a fund.
    /// @param fundId The id of the reward fund to be updated
    /// @param newRewardRate The new reward rate for the fund (includes the precision)
    function setRewardsPerSec(uint8 fundId, uint256 newRewardRate)
        public
        onlyOwner
    {
        // Update the total accumulated rewards here
        _updateFarmRewardData();

        // Update the reward rate
        uint256 oldRewardRate = rewardFunds[fundId].rewardsPerSec;
        rewardFunds[fundId].rewardsPerSec = newRewardRate;

        emit RewardRateUpdated(fundId, oldRewardRate, newRewardRate);
    }

    /// @notice Update the cooldown period
    /// @param newCooldownPeriod The new cooldown period (in seconds)
    function updateCooldownPeriod(uint256 newCooldownPeriod) public onlyOwner {
        uint256 oldCooldownPeriod = cooldownPeriod;
        cooldownPeriod = newCooldownPeriod;
        emit CooldownPeriodUpdated(oldCooldownPeriod, cooldownPeriod);
    }

    /// @notice Pause / UnPause the deposit
    function toggleDepositPause() public onlyOwner {
        isPaused = !isPaused;
        emit DepositPaused(isPaused);
    }

    // -------------------------------------------------------------------

    /// @notice Claim rewards for the user.
    /// @param account The user's address
    /// @param depositId The id of the deposit
    /// @dev NOTE: any function calling this internal
    ///     function should be marked as non-reentrant
    function _claimRewards(address account, uint256 depositId) internal {
        _updateFarmRewardData();

        Deposit storage userDeposit = deposits[account][depositId];
        Subscription[] storage depositSubs = subscriptions[userDeposit.tokenId];

        uint256 totalRewards = 0;
        uint256 numRewards = depositSubs.length;
        uint256[] memory rewards = new uint256[](numRewards);
        // Compute the rewards for each subscription.
        for (uint8 i = 0; i < numRewards; ++i) {
            // rewards = (liquidity * accRewardPerShare) / PREC - rewardDebt
            uint256 accRewards = (userDeposit.liquidity *
                rewardFunds[depositSubs[i].fundId].accRewardPerShare) / PREC;
            rewards[i] = accRewards - depositSubs[i].rewardDebt;
            depositSubs[i].rewardClaimed += rewards[i];
            totalRewards += rewards[i];

            // Update userRewardDebt for the subscritption
            // rewardDebt = liquidity * accRewardPerShare
            depositSubs[i].rewardDebt = accRewards;

            emit RewardsClaimed(
                account,
                depositSubs[i].fundId,
                userDeposit.tokenId,
                userDeposit.liquidity,
                rewardFunds[depositSubs[i].fundId].totalLiquidity,
                rewards[i]
            );
        }

        // Update the total rewards earned for the deposit
        userDeposit.totalRewardsClaimed += totalRewards;

        if (inEmergency) {
            // Record event in case of emergency
            emit EmergencyClaim(account);
        } else {
            // Transfer the rewards to the user
            IERC20(rewardToken).safeTransfer(account, totalRewards);
        }
    }

    /// @notice Add subscription to the reward fund for a deposit
    /// @param tokenId The tokenId of the deposit
    /// @param fundId The reward fund id
    /// @param liquidity The liquidity of the deposit
    function _subscribeRewardFund(
        uint8 fundId,
        uint256 tokenId,
        uint256 liquidity
    ) internal {
        require(fundId < rewardFunds.length, "Invalid fund id");
        // Subscribe to the reward fund
        // initialize user's reward debt
        require(
            subscriptions[tokenId].length < 2,
            "Can't subscribe more than 2 funds"
        );
        subscriptions[tokenId].push(
            Subscription({
                fundId: fundId,
                rewardDebt: (liquidity *
                    rewardFunds[fundId].accRewardPerShare) / PREC,
                rewardClaimed: 0
            })
        );

        rewardFunds[fundId].totalLiquidity += liquidity;
    }

    /// @notice Unsubscribe a reward fund from a deposit
    /// @param fundId The reward fund id
    /// @param account The user's address
    /// @param depositId The deposit id corresponding to the user
    /// @dev The rewards claimed from the reward fund is persisted in the event
    function _unsubscribeRewardFund(
        uint8 fundId,
        address account,
        uint256 depositId
    ) internal {
        require(fundId < rewardFunds.length, "Invalid fund id");
        Deposit storage userDeposit = deposits[account][depositId];

        // Unsubscribe from the reward fund
        Subscription[] storage depositSubs = subscriptions[userDeposit.tokenId];
        uint256 numFunds = depositSubs.length;
        for (uint256 i = 0; i < numFunds; ++i) {
            if (depositSubs[i].fundId == fundId) {
                // Persist the reward information
                uint256 rewardClaimed = depositSubs[i].rewardClaimed;

                // Delete the subscription from the list
                depositSubs[i] = depositSubs[numFunds - 1];
                depositSubs.pop();

                // Remove the liquidity from the reward fund
                rewardFunds[fundId].totalLiquidity -= userDeposit.liquidity;

                emit PoolUnsubscribed(
                    account,
                    userDeposit.tokenId,
                    fundId,
                    userDeposit.startTime,
                    block.timestamp,
                    rewardClaimed
                );

                break;
            }
        }
    }

    /// @notice Function to update the FarmRewardData for all funds
    function _updateFarmRewardData() internal {
        if (block.timestamp > lastFundUpdateTime) {
            uint256 time = block.timestamp - lastFundUpdateTime;
            // Update the two reward funds.
            for (uint8 i = 0; i < rewardFunds.length; ++i) {
                RewardFund storage fund = rewardFunds[i];
                if (fund.totalLiquidity > 0) {
                    fund.accRewardPerShare +=
                        (fund.rewardsPerSec * time * PREC) /
                        fund.totalLiquidity;
                }
            }
            lastFundUpdateTime = block.timestamp;
        }
    }

    /// @notice Validate the position for the pool and get Liquidity
    /// @param tokenId The tokenId of the position
    /// @dev the position must adhere to the price ranges
    /// @dev Only allow specific pool token to be staked.
    function _getLiquidity(uint256 tokenId) internal view returns (uint256) {
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

        ) = INFPM(NFPM).positions(tokenId);

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
}

