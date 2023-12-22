// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Math} from "./Math.sol";
import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ArcBaseWithRainbowRoad} from "./ArcBaseWithRainbowRoad.sol";
import {IFeeCollector} from "./IFeeCollector.sol";

// FeeCollectors pay out rewards for a given token based on the deposits that were received from the users
contract FeeCollector is ArcBaseWithRainbowRoad, IFeeCollector
{
    using SafeERC20 for IERC20;

    address public authorized;

    uint internal constant WEEK = 1 weeks;
    uint public constant DURATION = 7 days; // rewards are released every 7 days
    uint public constant PRECISION = 10 ** 18;
    uint public constant MAX_REWARD_TOKENS = 16; // max number of reward tokens that can be added

    uint public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => uint) public balanceLockExpires;

    mapping(address => mapping(uint => uint)) public tokenRewardsPerEpoch;
    mapping(address => uint) public periodFinish;
    mapping(address => mapping(address => uint)) public lastEarn;

    address[] public rewards;
    mapping(address => bool) public isReward;

    /// @notice A checkpoint for marking balance
    struct Checkpoint
    {
        uint timestamp;
        uint balanceOf;
    }

    /// @notice A checkpoint for marking supply
    struct SupplyCheckpoint
    {
        uint timestamp;
        uint supply;
    }

    /// @notice A record of balance checkpoints for each account, by index
    mapping (address => mapping (uint => Checkpoint)) public checkpoints;
    /// @notice The number of checkpoints for each account
    mapping (address => uint) public numCheckpoints;
    /// @notice A record of balance checkpoints for each token, by index
    mapping (uint => SupplyCheckpoint) public supplyCheckpoints;
    /// @notice The number of checkpoints
    uint public supplyNumCheckpoints;

    event Deposit(address indexed from, address account, uint amount);
    event Withdraw(address indexed from, address account, uint amount);
    event NotifyReward(address indexed from, address indexed reward, uint epoch, uint amount);
    event ClaimRewards(address indexed from, address indexed reward, uint amount);

    constructor(address _rainbowRoad, address _authorizedAccount) ArcBaseWithRainbowRoad(_rainbowRoad)
    {
        require(_authorizedAccount != address(0), 'Authorized account cannot be zero address');
        authorized = _authorizedAccount;
        _transferOwnership(rainbowRoad.team());
    }
    
    function setAuthorized(address _authorizedAccount) external onlyOwner
    {
        require(_authorizedAccount != address(0), 'Authorized account cannot be zero address');
        authorized = _authorizedAccount;
    }

    function _feeStart(uint timestamp) internal pure returns (uint)
    {
        return timestamp - (timestamp % (DURATION));
    }

    function getEpochStart(uint timestamp) public pure returns (uint)
    {
        uint feeStart = _feeStart(timestamp);
        uint feeEnd = feeStart + DURATION;
        return timestamp < feeEnd ? feeStart : feeStart + DURATION;
    }
    
    /// @dev Returns true if the balance is unlocked, false if locked.
    /// @param account The owner of the balance.
    function isBalanceLockExpired(address account) external view returns (bool) {
        return _isBalanceLockExpired(account);
    }
    
    /// @dev Returns true if the balance is unlocked, false if locked.
    /// @param account The owner of the balance.
    function _isBalanceLockExpired(address account) internal view returns (bool) {
        return balanceLockExpires[account] < block.timestamp;
    }

    /**
    * @notice Determine the prior balance for an account as of a block number
    * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
    * @param account The address of the account to check
    * @param timestamp The timestamp to get the balance at
    * @return The balance the account had as of the given block
    */
    function getPriorBalanceIndex(address account, uint timestamp) public view returns (uint)
    {
        uint nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].timestamp <= timestamp) {
            return (nCheckpoints - 1);
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].timestamp > timestamp) {
            return 0;
        }

        uint lower = 0;
        uint upper = nCheckpoints - 1;
        while (upper > lower) {
            uint center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.timestamp == timestamp) {
                return center;
            } else if (cp.timestamp < timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    function getPriorSupplyIndex(uint timestamp) public view returns (uint)
    {
        uint nCheckpoints = supplyNumCheckpoints;
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (supplyCheckpoints[nCheckpoints - 1].timestamp <= timestamp) {
            return (nCheckpoints - 1);
        }

        // Next check implicit zero balance
        if (supplyCheckpoints[0].timestamp > timestamp) {
            return 0;
        }

        uint lower = 0;
        uint upper = nCheckpoints - 1;
        while (upper > lower) {
            uint center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            SupplyCheckpoint memory cp = supplyCheckpoints[center];
            if (cp.timestamp == timestamp) {
                return center;
            } else if (cp.timestamp < timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    function _writeCheckpoint(address account, uint balance) internal
    {
        uint _timestamp = block.timestamp;
        uint _nCheckPoints = numCheckpoints[account];

        if (_nCheckPoints > 0 && checkpoints[account][_nCheckPoints - 1].timestamp == _timestamp) {
            checkpoints[account][_nCheckPoints - 1].balanceOf = balance;
        } else {
            checkpoints[account][_nCheckPoints] = Checkpoint(_timestamp, balance);
            numCheckpoints[account] = _nCheckPoints + 1;
        }
    }

    function _writeSupplyCheckpoint() internal
    {
        uint _nCheckPoints = supplyNumCheckpoints;
        uint _timestamp = block.timestamp;

        if (_nCheckPoints > 0 && supplyCheckpoints[_nCheckPoints - 1].timestamp == _timestamp) {
            supplyCheckpoints[_nCheckPoints - 1].supply = totalSupply;
        } else {
            supplyCheckpoints[_nCheckPoints] = SupplyCheckpoint(_timestamp, totalSupply);
            supplyNumCheckpoints = _nCheckPoints + 1;
        }
    }

    function rewardsListLength() external view returns (uint)
    {
        return rewards.length;
    }

    // returns the last time the reward was modified or periodFinish if the reward has ended
    function lastTimeRewardApplicable(address token) public view returns (uint)
    {
        return Math.min(block.timestamp, periodFinish[token]);
    }

    // allows a user to claim rewards for a given token
    function getReward(address[] memory tokens) external nonReentrant 
    {
        
        for (uint i = 0; i < tokens.length; i++) {
            uint _reward = earned(tokens[i], msg.sender);
            lastEarn[tokens[i]][msg.sender] = block.timestamp;
            if (_reward > 0) IERC20(tokens[i]).safeTransfer(msg.sender, _reward);

            emit ClaimRewards(msg.sender, tokens[i], _reward);
        }
    }

    function earned(address token, address account) public view returns (uint)
    {
        if (numCheckpoints[account] == 0) {
            return 0;
        }

        uint reward = 0;
        uint _ts = 0;
        uint _bal = 0;
        uint _supply = 1;
        uint _index = 0;
        uint _currTs = _feeStart(lastEarn[token][account]); // take epoch last claimed in as starting point

        _index = getPriorBalanceIndex(account, _currTs);
        _ts = checkpoints[account][_index].timestamp;
        _bal = checkpoints[account][_index].balanceOf;
        // accounts for case where lastEarn is before first checkpoint
        _currTs = Math.max(_currTs, _feeStart(_ts));

        // get epochs between current epoch and first checkpoint in same epoch as last claim
        uint numEpochs = (_feeStart(block.timestamp) - _currTs) / DURATION;

        if (numEpochs > 0) {
            for (uint256 i = 0; i < numEpochs; i++) {
                // get index of last checkpoint in this epoch
                _index = getPriorBalanceIndex(account, _currTs + DURATION);
                // get checkpoint in this epoch
                _ts = checkpoints[account][_index].timestamp;
                _bal = checkpoints[account][_index].balanceOf;
                // get supply of last checkpoint in this epoch
                _supply = supplyCheckpoints[getPriorSupplyIndex(_currTs + DURATION)].supply;
                if( _supply > 0 ) // prevent div by 0
                    reward += _bal * tokenRewardsPerEpoch[token][_currTs] / _supply;
                _currTs += DURATION;
            }
        }

        return reward;
    }

    function deposit(address account, uint amount) external onlyAuthorized nonReentrant whenNotPaused
    {
        balanceLockExpires[account] = block.timestamp + WEEK;
        totalSupply += amount;
        balanceOf[account] += amount;

        _writeCheckpoint(account, balanceOf[account]);
        _writeSupplyCheckpoint();

        emit Deposit(msg.sender, account, amount);
    }

    function withdraw(address account, uint amount) external onlyAuthorized nonReentrant whenNotPaused
    {
        require(_isBalanceLockExpired(account), "Balance is locked");
        require(balanceOf[account] >= amount, "Insufficient account balance");
        totalSupply -= amount;
        balanceOf[account] -= amount;

        _writeCheckpoint(account, balanceOf[account]);
        _writeSupplyCheckpoint();

        emit Withdraw(msg.sender, account, amount);
    }

    function left(address token) external view returns (uint)
    {
        uint adjustedTstamp = getEpochStart(block.timestamp);
        return tokenRewardsPerEpoch[token][adjustedTstamp];
    }

    function notifyRewardAmount(address token, uint amount) external nonReentrant
    {
        require(amount > 0, "Invalid amount");
        if (!isReward[token]) {
            require(rainbowRoad.tokens(IERC20Metadata(token).symbol()) != address(0), "Rewards tokens must be whitelisted");
            require(!rainbowRoad.blockedTokens(token), "Rewards token must not be blocked");
            require(rewards.length < MAX_REWARD_TOKENS, "Too many rewards tokens");
        }
        
        // bribes kick in at the start of next bribe period
        uint adjustedTstamp = getEpochStart(block.timestamp);
        uint epochRewards = tokenRewardsPerEpoch[token][adjustedTstamp];

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount); // Out of Gas here
        tokenRewardsPerEpoch[token][adjustedTstamp] = epochRewards + amount;

        periodFinish[token] = adjustedTstamp + DURATION;

        if (!isReward[token]) {
            isReward[token] = true;
            rewards.push(token);
        }

        emit NotifyReward(msg.sender, token, adjustedTstamp, amount);
    }

    function swapOutRewardToken(uint i, address oldToken, address newToken) external onlyOwner
    {
        require(rewards[i] == oldToken);
        isReward[oldToken] = false;
        isReward[newToken] = true;
        rewards[i] = newToken;
    }
    
    /// @dev Only calls from the authorized are accepted.
    modifier onlyAuthorized() 
    {
        require(authorized == msg.sender, "Not authorized");
        _;
    }
}
