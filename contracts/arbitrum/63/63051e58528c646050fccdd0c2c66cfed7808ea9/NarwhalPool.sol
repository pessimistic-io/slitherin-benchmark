// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;
import "./SafeERC20.sol";
import "./PairInfoInterface.sol";
import "./LimitOrdersInterface.sol";
import "./IVester.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";

interface ITradingVault {
    function deposit(uint _amount, address _user) external;
}

contract NarwhalPool is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Contracts & Addresses
    StorageInterface public immutable storageT;
    address public USDT;
    address public narToken;
    address public esToken;
    address public govFund;
    address public Vester;
    address public TradingVault;
    uint256 public MAX_INT = 2 ** 256 - 1;

    address public pendingGovFund;
    // Pool variables for NAR
    uint256 public accTokensPernarToken;
    uint256 public accUSDTPernarToken;
    uint256 public totalDeposited;
    uint256 public totalUSDTRewardsIncrement;

    // Mappings
    mapping(address => UserNwxRecords) public usernarrecords;
    mapping(address => bool) public allowedContracts;
    mapping(address => uint256) public cumulativeRewards;
    mapping(address => uint256) public averageStakedAmounts;
    mapping(address => mapping(address => uint256)) public depositBalances;
    mapping(address => uint256) public stakedAmounts;
    mapping(address => bool) public isTokenWhitelisted;
    mapping(address => uint256) public totalDepositedForToken;

    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 90 days;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    //Change back to 72 hours !!
    uint public withdrawTimelock = 1 minutes; // time
    bool public withdrawTimelockEnabled = false;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    struct UserNwxRecords {
        uint256 narDebtUSDT;
        uint256 amountInLockup;
        uint256 narLocked;
        uint256 esnarLocked;
        uint256 depositTimestamp;
    }

    // Pool stats
    uint256 public rewardsToken; // 1e18
    uint256 public rewardsUSDT; // usdtDecimals

    // Events
    event AddressUpdated(string name, address a);
    event ContractAllowed(address a, bool allowed);
    event RewardsDurationSet(uint256 rewardsDuration);
    event RewardsSet(uint256 rewards);

    constructor(address _tradingStorage, StorageInterface _storageT) {
        require(_tradingStorage != address(0), "ADDRESS_0");
        allowedContracts[_tradingStorage] = true;
        govFund = msg.sender;
        storageT = _storageT;
    }

    // GOV => UPDATE VARIABLES & MANAGE PAIRS

    // 0. Modifiers
    modifier onlyGov() {
        require(msg.sender == govFund, "GOV_ONLY");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    // ONLY FOR DECIMAL 18 tokens
    function setTokenWhitelisted(address _token, bool _status) external onlyGov {
        require(_token == narToken || _token == esToken, "Invalid token");
        isTokenWhitelisted[_token] = _status;
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyGov {
        require(
            block.timestamp > periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        require(_rewardsDuration >= 30 days && _rewardsDuration <= 730 days, "Out of range");
        rewardsDuration = _rewardsDuration;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardsDurationSet(_rewardsDuration);
    }

    function notifyRewardAmount(uint256 reward) external onlyGov updateReward(address(0)) {
        
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }
        IERC20(address(esToken)).safeTransferFrom(msg.sender, address(this), reward);
        uint balance = IERC20(address(esToken)).balanceOf(address(this));
        require(rewardRate <= balance.div(rewardsDuration), "Provided reward too high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardsSet(reward);
    }

    // Set addresses
    function setPendingGovFund(address _govFund) external onlyGov {
        require(_govFund != address(0), "ADDRESS_0");
        pendingGovFund = _govFund;
    }

    function confirmGovFund() external onlyGov {
        govFund = pendingGovFund;
        emit AddressUpdated("govFund", govFund);
    }

    function setVester(address _vester) external onlyGov {
        require(_vester != address(0), "ADDRESS_0");
        Vester = _vester;
        emit AddressUpdated("Vester", _vester);
    }

    function setEsToken(address _esToken) external onlyGov {
        require(address(_esToken) != address(0), "ADDRESS_0");
        esToken = _esToken;
        emit AddressUpdated("estoken", address(_esToken));
    }

    function setNARToken(address _narToken) external onlyGov {
        require(address(_narToken) != address(0), "ADDRESS_0");
        narToken = _narToken;
        emit AddressUpdated("nextoken", address(_narToken));
    }

    function setUSDT(address _USDT) external onlyGov {
        require(_USDT != address(0), "ADDRESS_0");
        USDT = _USDT;
        emit AddressUpdated("token", _USDT);
    }

    function setWithdrawTimelock(uint _withdrawTimelock) external onlyGov {
        require(_withdrawTimelock > 1 days, "Should be above 1 day");
        withdrawTimelock = _withdrawTimelock;
    }
    
    function setWithdrawTimelockEnabled() external onlyGov {
        withdrawTimelockEnabled = !withdrawTimelockEnabled;
    }

    function setTradingVault(address _tradingVault) external onlyGov {
        require(address(_tradingVault) != address(0), "ADDRESS_0");
        TradingVault = _tradingVault;
        emit AddressUpdated("token", address(_tradingVault));
    }

    function addAllowedContract(address c) external onlyGov {
        require(c != address(0), "ADDRESS_0");
        allowedContracts[c] = true;
        emit ContractAllowed(c, true);
    }

    function removeAllowedContract(address c) external onlyGov {
        require(c != address(0), "ADDRESS_0");
        allowedContracts[c] = false;
        emit ContractAllowed(c, false);
    }

    function increaseAccTokens(uint256 _amount) external {
        require(allowedContracts[msg.sender], "ONLY_ALLOWED_CONTRACTS");
        IERC20(USDT).safeTransferFrom(msg.sender, address(this), _amount);

        if (totalDeposited > 0) {
            accUSDTPernarToken += (_amount * 1e18) / totalDeposited;
            totalUSDTRewardsIncrement += _amount;
        }
    }

    function totalSupply() external view returns (uint256) {
        return totalDeposited;
    }

    function balanceOf(address account) external view returns (uint256) {
        uint256 stakedToken = userTotalBalance(account);
        return stakedToken;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalDeposited == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(totalDeposited)
            );
    }

    function earned(address account) public view returns (uint256) {
        uint256 stakedToken = userTotalBalance(account);
        return stakedToken.mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    function getUserTokenBalance(
        address _account
    ) external view returns (uint256) {
        return (stakedAmounts[_account]);
    }

    function getReservedAmount(address _account) external view returns (uint256) {
        UserNwxRecords storage unar = usernarrecords[_account];
        return (unar.amountInLockup);
    }

    function pendingRewardUSDTNARStake(
        address _account
    ) public view returns (uint) {
        if (totalDeposited == 0) {
            return 0;
        }
        UserNwxRecords storage unar = usernarrecords[_account];
        uint256 stakedToken = userTotalBalance(_account);
        uint256 pendings = (stakedToken * accUSDTPernarToken) /
            1e18 -
            unar.narDebtUSDT;
        return (pendings);
    }

    function getUserNARInfo(
        address _account
    ) external view returns (uint256, uint256) {
        UserNwxRecords storage unar = usernarrecords[_account];
        uint256 totalUserDeposited = stakedAmounts[_account];
        return (totalUserDeposited, unar.narDebtUSDT);
    }

    function _lockNAR(address _account, uint256 _amount) external {
        require(msg.sender == Vester, "Not the vesting contract");
        UserNwxRecords storage unar = usernarrecords[_account];
        stakedAmounts[_account] = stakedAmounts[_account].sub(_amount);
        unar.amountInLockup = unar.amountInLockup.add(_amount);

        uint256 amountDiv2 = _amount.div(2);
        uint256 narStaked = depositBalances[_account][address(narToken)];
        uint256 esnarStaked = depositBalances[_account][address(esToken)];

        if (amountDiv2 <= narStaked && amountDiv2 <= esnarStaked) {
            unar.narLocked += amountDiv2;
            unar.esnarLocked += amountDiv2;
        } else if (
            amountDiv2 <= narStaked &&
            amountDiv2 > esnarStaked &&
            _amount <= narStaked
        ) {
            unar.narLocked += _amount;
        } else if (
            amountDiv2 > narStaked &&
            amountDiv2 <= esnarStaked &&
            _amount <= esnarStaked
        ) {
            unar.esnarLocked += _amount;
        } else if (narStaked > esnarStaked && esnarStaked != 0) {
            unar.esnarLocked += _amount.sub(narStaked);
            unar.narLocked += _amount.sub(unar.esnarLocked);
        } else if (esnarStaked > narStaked && narStaked != 0) {
            unar.narLocked += _amount.sub(esnarStaked);
            unar.esnarLocked += _amount.sub(unar.narLocked);
        } else {
            revert("Adjust your staking balance");
        }
    }

    function _unLockNAR(address _account, uint256 _amount) external {
        require(msg.sender == Vester, "Not the vesting contract");
        UserNwxRecords storage unar = usernarrecords[_account];
        unar.amountInLockup = unar.amountInLockup.sub(_amount);
        stakedAmounts[_account] = stakedAmounts[_account].add(_amount);
        unar.narLocked = 0;
        unar.esnarLocked = 0;
    }

    // Harvest rewards
    function harvest(bool _compound) public updateReward(msg.sender) {
        UserNwxRecords storage unar = usernarrecords[msg.sender];
        uint256 narRewards;
        uint256 USDTRewardsNAR;

        if (totalDeposited > 0) {
            (narRewards, USDTRewardsNAR) = _harvest();
        }

        uint256 pendingTokens = narRewards;
        uint256 pendingUSDTTotal = USDTRewardsNAR;

        if (pendingTokens > 0) {
            rewards[msg.sender] = 0;
            uint256 nextCumulativeReward = cumulativeRewards[msg.sender].add(
                pendingTokens
            );
            averageStakedAmounts[msg.sender] = averageStakedAmounts[msg.sender]
                .mul(cumulativeRewards[msg.sender])
                .div(nextCumulativeReward)
                .add(stakedAmounts[msg.sender].add(unar.amountInLockup))
                .mul((pendingTokens))
                .div(nextCumulativeReward);
            cumulativeRewards[msg.sender] = nextCumulativeReward;

            if (!_compound) {
                IERC20(esToken).safeTransfer(msg.sender, pendingTokens);
            } else {
                stakedAmounts[msg.sender] += pendingTokens;
                totalDeposited += pendingTokens;
                totalDepositedForToken[address(esToken)] += pendingTokens;

                uint256 stakedToken = userTotalBalance(msg.sender);
                unar.narDebtUSDT = (stakedToken * accUSDTPernarToken) / 1e18;
                if (withdrawTimelockEnabled) {
                    unar.depositTimestamp = block.timestamp;
                }
                depositBalances[msg.sender][address(esToken)] += pendingTokens;
            }

        }

        if (pendingUSDTTotal > 0) {
            if (_compound) {
                IERC20(USDT).approve(TradingVault, pendingUSDTTotal);
                ITradingVault(TradingVault).deposit(
                    pendingUSDTTotal,
                    msg.sender
                );
            } else {
                IERC20(USDT).safeTransfer(msg.sender, pendingUSDTTotal);
            }
        }
    }

    function _harvest() internal returns (uint256, uint256) {
        UserNwxRecords storage unar = usernarrecords[msg.sender];
        uint pendingES = rewards[msg.sender];
        uint pendingUSDT = pendingRewardUSDTNARStake(msg.sender);

        uint256 stakedToken = userTotalBalance(msg.sender);
        unar.narDebtUSDT = (stakedToken * accUSDTPernarToken) / 1e18;
        rewardsUSDT += pendingUSDT;
        rewardsToken += pendingES;

        return (pendingES, pendingUSDT);
    }

    /**@notice Stakes the specified amount of tokens
    @param amount The amount of tokens to be staked
    @param _tokenAddress The address of the token being staked
    @dev Only users with whitelisted tokens can stake ONLY FOR DECIMAL 18 TOKENS
    /** */
    function stake(uint amount, address _tokenAddress) external nonReentrant updateReward(msg.sender) {
        require(isTokenWhitelisted[_tokenAddress], "Token not whitelisted");
        UserNwxRecords storage unar = usernarrecords[msg.sender];
        harvest(false);
        IERC20(address(_tokenAddress)).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        totalDeposited += amount;
        totalDepositedForToken[_tokenAddress] += amount;
        stakedAmounts[msg.sender] += amount;

        uint256 stakedToken = userTotalBalance(msg.sender);
        unar.narDebtUSDT = (stakedToken * accUSDTPernarToken) / 1e18;
        if (withdrawTimelockEnabled) {
            unar.depositTimestamp = block.timestamp;
        }

        depositBalances[msg.sender][_tokenAddress] += amount;
    }

    /**

    @notice Unstake amount of _tokenAddress
    @param amount The amount of tokens to be unstaked
    @param _tokenAddress The address of the tokens to be unstaked
    @dev This function allows a user to unstake their tokens
    */
    function unstake(uint amount, address _tokenAddress) external nonReentrant updateReward(msg.sender) {
        require(isTokenWhitelisted[_tokenAddress], "Token not whitelisted");
        require(
            amount <= depositBalances[msg.sender][_tokenAddress],
            "AMOUNT_TOO_BIG"
        );
        UserNwxRecords storage unar = usernarrecords[msg.sender];
        
        if (withdrawTimelockEnabled) {
            require(block.timestamp >= unar.depositTimestamp + withdrawTimelock,"TOO_EARLY");
        }

        harvest(false);
        uint256 am;
        uint256 availToWithdraw;
        bool lockup = false;
        if (unar.amountInLockup > 0) {
            (availToWithdraw, lockup) = userAvailToWithdraw(
                msg.sender,
                _tokenAddress
            );
        } else {
            availToWithdraw = depositBalances[msg.sender][_tokenAddress];
        }
        if (lockup) {
            require(amount <= availToWithdraw, "Amount too high");
            require(availToWithdraw != 0, "Nothing to withdraw");
            am = amount;
        } else {
            require(
                amount <= depositBalances[msg.sender][_tokenAddress],
                "Amount too high"
            );
            require(availToWithdraw != 0, "Nothing to withdraw");
            am = amount;
        }

        totalDeposited -= am;
        totalDepositedForToken[_tokenAddress] -= am;
        stakedAmounts[msg.sender] -= am;

        uint256 stakedToken = userTotalBalance(msg.sender);
        unar.narDebtUSDT = (stakedToken * accUSDTPernarToken) / 1e18;

        depositBalances[msg.sender][_tokenAddress] -= am;

        IERC20(_tokenAddress).safeTransfer(msg.sender, am);
    }

    /**
    @notice Check the available amount that a user can withdraw
    @param _user The address of the user
    @param _tokenAddress The address of the narToken to check
    @return The amount of tokens available to withdraw and a boolean indicating if the amount is locked up
    @dev This function checks if a user has any nar/es/Tokens locked up, and if so, how many are available to withdraw
    */
    function userAvailToWithdraw(
        address _user,
        address _tokenAddress
    ) public view returns (uint256, bool) {
        UserNwxRecords storage unar = usernarrecords[_user];

        uint256 narStaked = depositBalances[_user][address(narToken)];
        uint256 esnarStaked = depositBalances[_user][address(esToken)];

        uint256 availToWithdraw;
        if (stakedAmounts[_user] == 0) {
            availToWithdraw = 0;
        } else if (
            unar.narLocked > 0 && _tokenAddress == address(narToken)
        ) {
            availToWithdraw = narStaked.sub(unar.narLocked);
        } else if (
            unar.esnarLocked > 0 && _tokenAddress == address(esToken)
        ) {
            availToWithdraw = esnarStaked.sub(unar.esnarLocked);
        }

        return (availToWithdraw, true);
    }

    /**
    @notice Check the total balance of a user's staked nar/es/Tokens
    @param _user The address of the user
    @return The total amount of nar/es/Tokens staked by the user
    @dev This function returns the total amount of nar/es/Tokens staked by the user, including any locked up tokens
    */
    function userTotalBalance(address _user) public view returns (uint256) {
        UserNwxRecords storage unar = usernarrecords[msg.sender];
        uint256 staked;
        if (unar.amountInLockup > 0) {
            staked = unar.amountInLockup.add(stakedAmounts[_user]);
        } else {
            staked = stakedAmounts[_user];
        }
        return staked;
    }
}

