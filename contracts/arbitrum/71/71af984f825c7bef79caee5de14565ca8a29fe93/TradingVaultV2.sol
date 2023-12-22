// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./ERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./PairInfoInterface.sol";
import "./LimitOrdersInterface.sol";

contract NarwhalTradingVault is ERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public esnar;
    StorageInterface public immutable storageT;
    uint256 public rewardsToken; // 1e6
    address public Vester;
    address public USDT;

    // 3. Staking
    uint public withdrawTimelock; // time

    // STATE
    // 1. USDT balance
    uint256 public currentBalanceUSDT; // 1e6

    // 2. USDT staking rewards
    uint public totalRewardsDistributed; // 1e6

    // 4. Mappings
    struct User {
        uint256 depositTimestamp;
        uint256 debtToken;
        uint256 amountInLockup;
    }
    mapping(address => User) public users;
    mapping(address => uint) public USDTToClaim;
    mapping(address => uint256) public cumulativeRewards;
    mapping(address => uint256) public averageStakedAmounts;
    mapping(address => uint256) public stakedAmounts;
    mapping(address => bool) public allowed;

    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public rewardsDuration = 90 days;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => bool) public allowedToInteract;

    // EVENTS
    event Deposited(
        address caller,
        uint amount,
        uint newCurrentBalanceUSDT,
        uint shares
    );
    event Withdrawn(
        address caller,
        uint amount,
        uint newCurrentBalanceUSDT,
        uint shares
    );
    event Sent(
        address caller,
        address trader,
        uint amount,
        uint newCurrentBalanceUSDT
    );
    event ToClaim(
        address caller,
        address trader,
        uint amount,
        uint currentBalanceUSDT
    );
    event Claimed(address trader, uint amount, uint newCurrentBalanceUSDT);

    event ReceivedFromTrader(
        address caller,
        address trader,
        uint USDTAmount,
        uint vaultFeeUSDT,
        uint newCurrentBalanceUSDT
    );
    event NumberUpdated(string name, uint value);
    event AllowedToInteractSet(address indexed sender, bool status);
    event RewardsDurationSet(uint256 rewardsDuration);
    event RewardTokenSet(address indexed esnar);
    event VesterSet(address indexed vester);
    event UsdtSet(address indexed usdt);
    event RewardsSet(uint256 rewards);

    constructor(
        StorageInterface _storageT,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        require(address(_storageT) != address(0), "ADDRESS_0");
        storageT = _storageT;
    }

    modifier onlyGov() {
        require(msg.sender == storageT.gov(), "GOV_ONLY");
        _;
    }
    modifier onlyCallbacks() {
        require(msg.sender == storageT.callbacks() || allowedToInteract[msg.sender], "NOT_ALLOWED");
        _;
    }

    function setAllowedToInteract(address _sender, bool _status) public onlyGov {
        allowedToInteract[_sender] = _status;
        emit AllowedToInteractSet(_sender, _status);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyGov {
        require(
            block.timestamp > periodFinish,
            "Must complete previous rewards period"
        );
        require(_rewardsDuration >= 30 days && _rewardsDuration <= 730 days, "Out of range");
        rewardsDuration = _rewardsDuration;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardsDurationSet(_rewardsDuration);
    }

    function setRewardToken(address _esnar) external onlyGov {
        require(address(_esnar) != address(0), "ADDRESS_0");
        require(address(esnar) == address(0), "ALREADY_SET");
        esnar = _esnar;
        emit RewardTokenSet(_esnar);
    }

    function setVester(address _vester) external onlyGov {
        require(_vester != address(0), "ADDRESS_0");
        Vester = _vester;
        emit VesterSet(_vester);
    }

    function setUSDT(address _usdt) public onlyGov {
        require(address(_usdt) != address(0), "ADDRESS_0");
        require(address(USDT) == address(0), "ALREADY_SET");
        USDT = _usdt;
        emit UsdtSet(_usdt);
    }

    function setWithdrawTimelock(uint _withdrawTimelock) external onlyGov {
        require(_withdrawTimelock > 1 days, "Should be above 1 day");
        withdrawTimelock = _withdrawTimelock;
        emit NumberUpdated("withdrawTimelock", _withdrawTimelock);
    }

    function setAllowed(address _sender, bool _status) public onlyOwner {
        allowed[_sender] = _status;
        emit AllowedToInteractSet(_sender, _status);
    }


    function updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    function notifyRewardAmount(uint256 reward) external onlyGov  {
        updateReward(address(0));
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }
        IERC20(address(esnar)).safeTransferFrom(msg.sender, address(this), reward);
        uint currBalance = IERC20(address(esnar)).balanceOf(address(this));
        require(rewardRate <= currBalance.div(rewardsDuration), "Provided reward too high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardsSet(reward);
    }

    function balance() public view returns (uint256) {
        uint256 totalVaultBalance = currentBalanceUSDT;
        return (totalVaultBalance);
    }

    function getUserTokenBalance(
        address _account
    ) public view returns (uint256) {
        User storage u = users[_account];
        uint256 stakedToken;
        if (u.amountInLockup > 0) {
            stakedToken = u.amountInLockup.add(stakedAmounts[_account]);
        } else {
            stakedToken = stakedAmounts[_account];
        }
        return (stakedToken);
    }

    function getPricePerFullShare() public view returns (uint256) {
        return
            totalSupply() == 0 ? 10**storageT.USDT().decimals() : balance().mul(1e18).div(totalSupply());
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e6).div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        uint256 stakedToken = userTotalBalance(account);
        return stakedToken.mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e6).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    function _lockNAR(address _account, uint256 _amount) public {
        require(msg.sender == Vester, "Not the vesting contract");
        User storage u = users[_account];
        stakedAmounts[_account] = stakedAmounts[_account].sub(_amount);
        u.amountInLockup = u.amountInLockup.add(_amount);
    }

    function _unLockNAR(address _account, uint256 _amount) public {
        require(msg.sender == Vester, "Not the vesting contract");
        User storage u = users[_account];
        u.amountInLockup = u.amountInLockup.sub(_amount);
        stakedAmounts[_account] = stakedAmounts[_account].add(_amount);
    }

    // Harvest rewards
    function harvest(address _user) public {
        if (balance() == 0) {
            return;
        }

        address user;
        if (allowed[msg.sender]) {
            user = _user;
        } else {
            user = msg.sender;
        }
        updateReward(user);

        User storage u = users[user];

        uint pendingTokens = rewards[user];

        if (pendingTokens > 0) {
            rewards[user] = 0;
            uint256 nextCumulativeReward = cumulativeRewards[user].add(
                pendingTokens
            );
            averageStakedAmounts[user] = averageStakedAmounts[user]
                .mul(cumulativeRewards[user])
                .div(nextCumulativeReward)
                .add(stakedAmounts[user].add(u.amountInLockup))
                .mul((pendingTokens))
                .div(nextCumulativeReward);
            cumulativeRewards[user] = nextCumulativeReward;
            rewardsToken += pendingTokens;
            IERC20(esnar).safeTransfer(user, pendingTokens);
        }
    }

    function depositAll(address _user) external {
        deposit(IERC20(USDT).balanceOf(msg.sender), _user);
    }

    function deposit(uint _amount, address _user) public nonReentrant {
        require(_amount > 0, "AMOUNT_0");
        address user;
        if (allowed[msg.sender]) {
            user = _user;
        } else {
            user = msg.sender;
        }

        User storage u = users[user];

        require(storageT.USDT().transferFrom(msg.sender, address(this), _amount));
        harvest(user);

        uint256 shares = 0;
        uint256 SCALE = 10 ** decimals() / 10 ** storageT.USDT().decimals();
        if (totalSupply() == 0) {
            require(_amount > 1000,"Not Enough Shares for first mint");
            shares = (_amount-1000) * SCALE;
            _mint(address(this),1000 * SCALE);
        } else {
            shares = (_amount.mul(totalSupply())).div(currentBalanceUSDT);
        }
        require(shares != 0, "Zero shares minted");
        
        currentBalanceUSDT += _amount;

        _mint(user, shares);
        stakedAmounts[user] = stakedAmounts[user].add(shares);
        u.depositTimestamp = block.timestamp;

        emit Deposited(user, _amount, currentBalanceUSDT, shares);
    }

    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    function withdraw(uint _shares) public nonReentrant {
        require(_shares > 0, "AMOUNT_0");
        require(
            _shares <= stakedAmounts[msg.sender],
            "Cant withdraw more than your balance"
        );

        User storage u = users[msg.sender];
        harvest(msg.sender);
        uint256 userAsset;
        userAsset = (balance().mul(_shares)).div(totalSupply());

        require(
            block.timestamp >= u.depositTimestamp + withdrawTimelock,
            "TOO_EARLY"
        );
        _burn(msg.sender, _shares);
        currentBalanceUSDT -= userAsset;
        stakedAmounts[msg.sender] = stakedAmounts[msg.sender].sub(_shares);
        IERC20(USDT).safeTransfer(msg.sender, userAsset);

        emit Withdrawn(msg.sender, userAsset, currentBalanceUSDT, _shares);
    }

    function userTotalBalance(address _user) public view returns (uint256) {
        User storage u = users[_user];
        uint256 staked;
        if (u.amountInLockup > 0) {
            staked = u.amountInLockup.add(stakedAmounts[_user]);
        } else {
            staked = stakedAmounts[_user];
        }
        return staked;
    }

    // USDT incentives
    function distributeRewardUSDT(
        uint _amount,
        bool _send
    ) public onlyCallbacks {
        currentBalanceUSDT = currentBalanceUSDT.add(_amount);
        totalRewardsDistributed += _amount;
        if (_send) {
            IERC20(USDT).safeTransferFrom(msg.sender, address(this), _amount);
        }
    }

    // Handle traders USDT when a trade is closed
    function sendUSDTToTrader(
        address _trader,
        uint _amount
    ) external onlyCallbacks {
        if (_amount < currentBalanceUSDT) {
            currentBalanceUSDT = currentBalanceUSDT.sub(_amount);
            IERC20(USDT).safeTransfer(_trader, _amount);
            emit Sent(msg.sender, _trader, _amount, currentBalanceUSDT);
        } else {
            USDTToClaim[_trader] += _amount;
            emit ToClaim(msg.sender, _trader, _amount, currentBalanceUSDT);
        }
    }

    function claimUSDT() external {
        uint amount = USDTToClaim[msg.sender];
        require(amount > 0, "NOTHING_TO_CLAIM");
        require(currentBalanceUSDT > amount, "BALANCE_TOO_LOW");

        unchecked {
            currentBalanceUSDT -= amount;
        }
        USDTToClaim[msg.sender] = 0;
        IERC20(USDT).safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, amount, currentBalanceUSDT);
    }

    // Handle USDT from opened trades
    function receiveUSDTFromTrader(
        address _trader,
        uint _amount,
        uint _vaultFee,
        bool _send
    ) external onlyCallbacks {
        currentBalanceUSDT += _amount;
        storageT.transferUSDT(address(storageT), address(this), _amount);
        distributeRewardUSDT(_vaultFee, _send);
        emit ReceivedFromTrader(
            msg.sender,
            _trader,
            _amount,
            _vaultFee,
            currentBalanceUSDT
        );
    }
}

