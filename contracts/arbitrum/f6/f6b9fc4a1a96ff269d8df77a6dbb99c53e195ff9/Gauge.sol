// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./Math.sol";

import "./IFeeDistributor.sol";
import "./IERC20.sol";
import "./IGauge.sol";
import "./IPair.sol";
import "./IVoter.sol";
import "./IVotingEscrow.sol";

// Gauges are used to incentivize pools, they emit reward tokens over 7 days for staked LP tokens
contract Gauge is IGauge, Initializable {
    address public stake; // the LP token that needs to be staked for rewards
    address public _ve; // the ve token used for gauges
    address public feeDistributor;
    address public voter;

    uint256 public derivedSupply;
    mapping(address => uint256) public derivedBalances;

    uint256 internal constant DURATION = 7 days; // rewards are released over 7 days
    uint256 internal constant PRECISION = 10 ** 18;

    mapping(address => uint256) public pendingRewardRate;
    mapping(address => bool) public isStarted;
    mapping(address => uint256) public rewardRate;
    mapping(address => uint256) public periodFinish;
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => uint256) public rewardPerTokenStored;
    mapping(address => mapping(address => uint256)) public storedRewardsPerUser;

    mapping(address => mapping(address => uint256))
        public userRewardPerTokenStored;

    mapping(address => uint256) public tokenIds;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    address[] public rewards;
    mapping(address => bool) public isReward;

    bool public isForPair;

    uint256 internal _unlocked;

    event Deposit(address indexed from, uint256 tokenId, uint256 amount);
    event Withdraw(address indexed from, uint256 tokenId, uint256 amount);
    event NotifyReward(
        address indexed from,
        address indexed reward,
        uint256 amount
    );
    event ClaimFees(address indexed from, uint256 claimed0, uint256 claimed1);
    event ClaimRewards(
        address indexed from,
        address indexed reward,
        uint256 amount
    );

    modifier onlyAdmin() {
        require(
            msg.sender == 0x9314fC5633329d285F744108D637E1222CEbae1c,
            "!admin"
        );
        _;
    }

    function initialize(
        address _stake,
        address _bribe,
        address __ve,
        address _voter,
        bool _forPair,
        address[] memory _allowedRewardTokens
    ) external initializer {
        stake = _stake;
        feeDistributor = _bribe;
        _ve = __ve;
        voter = _voter;
        isForPair = _forPair;

        for (uint256 i; i < _allowedRewardTokens.length; ++i) {
            if (_allowedRewardTokens[i] != address(0)) {
                rewards.push(_allowedRewardTokens[i]);
                isReward[_allowedRewardTokens[i]] = true;
            }
        }

        _unlocked = 1;
    }

    // simple re-entrancy check
    modifier lock() {
        require(_unlocked == 1);
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    function claimFees()
        external
        lock
        returns (uint256 claimed0, uint256 claimed1)
    {
        return _claimFees();
    }

    function _claimFees()
        internal
        returns (uint256 claimed0, uint256 claimed1)
    {
        if (!isForPair) {
            return (0, 0);
        }
        (address _token0, address _token1) = IPair(stake).tokens();

        // check actual balances for compatibility with fee on transfer tokens.
        uint balanceBefore0 = IERC20(_token0).balanceOf(address(this));
        uint balanceBefore1 = IERC20(_token1).balanceOf(address(this));
        IPair(stake).claimFees();
        uint balanceAfter0 = IERC20(_token0).balanceOf(address(this));
        uint balanceAfter1 = IERC20(_token1).balanceOf(address(this));

        claimed0 = balanceAfter0 - balanceBefore0;
        claimed1 = balanceAfter1 - balanceBefore1;

        if (claimed0 > 0 || claimed1 > 0) {
            IERC20(_token0).approve(feeDistributor, claimed0);
            IFeeDistributor(feeDistributor).notifyRewardAmount(
                _token0,
                claimed0
            );

            IERC20(_token1).approve(feeDistributor, claimed1);
            IFeeDistributor(feeDistributor).notifyRewardAmount(
                _token1,
                claimed1
            );

            emit ClaimFees(msg.sender, claimed0, claimed1);
        }
    }

    function rewardsListLength() external view returns (uint256) {
        return rewards.length;
    }

    // returns the last time the reward was modified or periodFinish if the reward has ended
    function lastTimeRewardApplicable(
        address token
    ) public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish[token]);
    }

    function earned(
        address token,
        address account
    ) public view returns (uint256) {
        return
            (derivedBalances[account] *
                (rewardPerToken(token) -
                    userRewardPerTokenStored[account][token])) /
            PRECISION +
            storedRewardsPerUser[account][token];
    }

    // Only the tokens you claim will get updated.
    function getReward(address account, address[] memory tokens) public lock {
        require(msg.sender == account || msg.sender == voter);
        _unlocked = 1;
        IVoter(voter).distribute(address(this));
        _unlocked = 2;

        // update all user rewards regardless of tokens they are claiming
        address[] memory _rewards = rewards;
        uint256 len = _rewards.length;
        for (uint256 i; i < len; ++i) {
            if (isReward[_rewards[i]]) {
                if (!isStarted[_rewards[i]]) {
                    initializeRewardsDistribution(_rewards[i]);
                }
                updateRewardPerToken(_rewards[i], account);
            }
        }
        // transfer only the rewards they are claiming
        len = tokens.length;
        for (uint256 i; i < len; ++i){
            uint256 _reward = storedRewardsPerUser[account][tokens[i]];
            if (_reward > 0) {
                storedRewardsPerUser[account][tokens[i]] = 0;
                _safeTransfer(tokens[i], account, _reward);
                emit ClaimRewards(account, tokens[i], _reward);
            }        
        }

        uint256 _derivedBalance = derivedBalances[account];
        derivedSupply -= _derivedBalance;
        _derivedBalance = derivedBalance(account);
        derivedBalances[account] = _derivedBalance;
        derivedSupply += _derivedBalance;
    }

    function rewardPerToken(address token) public view returns (uint256) {
        if (derivedSupply == 0) {
            return rewardPerTokenStored[token];
        }
        return
            rewardPerTokenStored[token] +
            (((lastTimeRewardApplicable(token) -
                Math.min(lastUpdateTime[token], periodFinish[token])) *
                rewardRate[token] *
                PRECISION) / derivedSupply);
    }

    function derivedBalance(address account) public view returns (uint256) {
        uint256 _tokenId = tokenIds[account];
        uint256 _balance = balanceOf[account];
        uint256 _derived = (_balance * 40) / 100;
        uint256 _adjusted = 0;
        uint256 _supply = IERC20(_ve).totalSupply();
        if (account == IVotingEscrow(_ve).ownerOf(_tokenId) && _supply > 0) {
            _adjusted = IVotingEscrow(_ve).balanceOfNFT(_tokenId);
            _adjusted = (((totalSupply * _adjusted) / _supply) * 60) / 100;
        }
        return Math.min((_derived + _adjusted), _balance);
    }

    function depositAll(uint256 tokenId) external {
        deposit(IERC20(stake).balanceOf(msg.sender), tokenId);
    }

    function deposit(uint256 amount, uint256 tokenId) public lock {
        require(amount > 0);

        address[] memory _rewards = rewards;
        uint256 len = _rewards.length;

        for (uint256 i; i < len; ++i) {
            if (!isStarted[_rewards[i]]) {
                initializeRewardsDistribution(_rewards[i]);
            }
            updateRewardPerToken(_rewards[i], msg.sender);
        }

        _safeTransferFrom(stake, msg.sender, address(this), amount);
        totalSupply += amount;
        balanceOf[msg.sender] += amount;

        if (tokenId > 0) {
            require(IVotingEscrow(_ve).ownerOf(tokenId) == msg.sender);
            if (tokenIds[msg.sender] == 0) {
                tokenIds[msg.sender] = tokenId;
                IVoter(voter).attachTokenToGauge(tokenId, msg.sender);
            }
            require(tokenIds[msg.sender] == tokenId);
        } else {
            tokenId = tokenIds[msg.sender];
        }

        uint256 _derivedBalance = derivedBalances[msg.sender];
        derivedSupply -= _derivedBalance;
        _derivedBalance = derivedBalance(msg.sender);
        derivedBalances[msg.sender] = _derivedBalance;
        derivedSupply += _derivedBalance;

        IVoter(voter).emitDeposit(tokenId, msg.sender, amount);
        emit Deposit(msg.sender, tokenId, amount);
    }

    function withdrawAll() external {
        withdraw(balanceOf[msg.sender]);
    }

    function withdraw(uint256 amount) public {
        uint256 tokenId = 0;
        if (amount == balanceOf[msg.sender]) {
            tokenId = tokenIds[msg.sender];
        }
        withdrawToken(amount, tokenId);
    }

    function withdrawToken(uint256 amount, uint256 tokenId) public lock {
        require(amount > 0);

        address[] memory _rewards = rewards;
        uint256 len = _rewards.length;

        for (uint256 i; i < len; ++i) {
            updateRewardPerToken(_rewards[i], msg.sender);
        }

        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        _safeTransfer(stake, msg.sender, amount);

        if (tokenId > 0) {
            require(tokenId == tokenIds[msg.sender]);
            tokenIds[msg.sender] = 0;
            IVoter(voter).detachTokenFromGauge(tokenId, msg.sender);
        } else {
            tokenId = tokenIds[msg.sender];
        }

        uint256 _derivedBalance = derivedBalances[msg.sender];
        derivedSupply -= _derivedBalance;
        _derivedBalance = derivedBalance(msg.sender);
        derivedBalances[msg.sender] = _derivedBalance;
        derivedSupply += _derivedBalance;

        IVoter(voter).emitWithdraw(tokenId, msg.sender, amount);
        emit Withdraw(msg.sender, tokenId, amount);
    }

    function left(address token) external view returns (uint256) {
        if (block.timestamp >= periodFinish[token]) return 0;
        uint256 _remaining = periodFinish[token] - block.timestamp;
        return _remaining * rewardRate[token];
    }

    // @dev rewardRate and periodFinish is set on first deposit if totalSupply == 0 or first interaction after whitelisting. If msg.sender == governance and totalSupply > 0 reward is started immediately.
    function notifyRewardAmount(address token, uint256 amount) external lock {
        require(token != stake);
        require(amount > 0);
        rewardPerTokenStored[token] = rewardPerToken(token);
        _claimFees();
        // Check actual amount transferred for compatibility with fee on transfer tokens.
        uint balanceBefore = IERC20(token).balanceOf(address(this));
        _safeTransferFrom(token, msg.sender, address(this), amount);
        uint balanceAfter = IERC20(token).balanceOf(address(this));
        amount = balanceAfter - balanceBefore;
        uint _rewardRate = amount / DURATION;

        if (isStarted[token]) {
            if (block.timestamp >= periodFinish[token]) {
                rewardRate[token] = _rewardRate;
            } else {
                uint256 _remaining = periodFinish[token] - block.timestamp;
                uint256 _left = _remaining * rewardRate[token];
                require(amount > _left);
                rewardRate[token] = (amount + _left) / DURATION;
            }
            periodFinish[token] = block.timestamp + DURATION;
            lastUpdateTime[token] = block.timestamp;
        } else {
            if (pendingRewardRate[token] > 0) {
                uint256 _left = DURATION * pendingRewardRate[token];
                pendingRewardRate[token] = (amount + _left) / DURATION;
            } else {
                pendingRewardRate[token] = _rewardRate;
            }
        }
        if (msg.sender == voter) {
            if (!isReward[token]) {
                isReward[token] = true;
                rewards.push(token);
            }
            if (!isStarted[token] && totalSupply > 0) {
                initializeRewardsDistribution(token);
            }
        }
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(
            rewardRate[token] <= balance / DURATION,
            "Provided reward too high"
        );
        if (!isStarted[token]) {
            require(
                pendingRewardRate[token] <= balance / DURATION,
                "Provided reward too high"
            );
        }

        emit NotifyReward(msg.sender, token, amount);
    }

    function initializeRewardsDistribution(address token) internal {
        isStarted[token] = true;
        rewardRate[token] = pendingRewardRate[token];
        lastUpdateTime[token] = block.timestamp;
        periodFinish[token] = block.timestamp + DURATION;
        pendingRewardRate[token] = 0;
    }

    function whitelistNotifiedRewards(address token) external {
        require(msg.sender == voter);
        if (!isReward[token]) {
            isReward[token] = true;
            rewards.push(token);
        }
        if (!isStarted[token] && totalSupply > 0) {
            initializeRewardsDistribution(token);
        }
    }

    function getRewardTokenIndex(address token) public view returns (uint256) {
        address[] memory _rewards = rewards;
        uint256 len = _rewards.length;

        for (uint256 i; i < len; ++i) {
            if (_rewards[i] == token) {
                return i;
            }
        }
        return 0;
    }

    function removeRewardWhitelist(address token) external {
        require(msg.sender == voter);
        if (!isReward[token]) {
            return;
        }
        isReward[token] = false;
        uint256 idx = getRewardTokenIndex(token);
        uint256 len = rewards.length;
        for (uint256 i = idx; i < len - 1; ++i) {
            rewards[i] = rewards[i + 1];
        }
        rewards.pop();
    }

    function poke(address account) external {
        // Update reward rates and user rewards
        for (uint256 i; i < rewards.length; ++i) {
            updateRewardPerToken(rewards[i], account);
        }
        // Update user boosted balance and total boosted balance
        uint256 _derivedBalance = derivedBalances[account];
        derivedSupply -= _derivedBalance;
        _derivedBalance = derivedBalance(account);
        derivedBalances[account] = _derivedBalance;
        derivedSupply += _derivedBalance;
    }

    function updateRewardPerToken(address token, address account) internal {
        rewardPerTokenStored[token] = rewardPerToken(token);
        lastUpdateTime[token] = lastTimeRewardApplicable(token);
        storedRewardsPerUser[account][token] = earned(token, account);
        userRewardPerTokenStored[account][token] = rewardPerTokenStored[token];
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                value
            )
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeApprove(
        address token,
        address spender,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    // this is a temporary function to notify trapped fees into FeeDistributor
    // all these actions (upgrade, rescue, rollback) will happen in one timelocked tx)
    function rescueTrappedFees(
        address[] memory tokens,
        uint256[] memory amounts
    ) external onlyAdmin {
        for (uint256 i; i < tokens.length; i++) {
            // this function cannot withdraw LP token
            require(tokens[i] != stake, "!stake");

            IERC20(tokens[i]).approve(feeDistributor, amounts[i]);
            IFeeDistributor(feeDistributor).notifyRewardAmount(
                tokens[i],
                amounts[i]
            );
        }
    }

    function removeExtraRewardToken(
        uint256 index,
        uint256 duplicateIndex
    ) external onlyAdmin {
        require(index < duplicateIndex);
        require(rewards[index] == rewards[duplicateIndex]);

        uint len = rewards.length;
        for (uint i = duplicateIndex; i < len - 1; ++i) {
            rewards[i] = rewards[i + 1];
        }
        rewards.pop();
    }
}

