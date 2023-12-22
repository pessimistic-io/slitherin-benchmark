// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

contract LyLevel is Initializable, OwnableUpgradeable, IERC20 {
    using SafeERC20 for IERC20;

    struct BatchInfo {
        uint256 rewardPerShare;
        uint256 totalBalance;
        uint256 allocatedTime;
    }

    string public constant name = "Level Loyalty Token";
    string public constant symbol = "lyLVL";
    uint8 public constant decimals = 18;
    uint256 public constant PRECISION = 1e6;
    uint256 public constant MIN_EPOCH_DURATION = 1 days;
    uint256 public constant MAX_BATCH_VESTING_DURATION = 7 days;
    IERC20 public constant rewardToken = IERC20(0xB64E280e9D1B5DbEc4AcceDb2257A87b400DB149);

    address public minter;
    uint256 public currentBatchId;

    mapping(uint256 batchId => BatchInfo) public batches;
    mapping(uint256 batchId => mapping(address owner => uint256)) public _balances;
    mapping(address owner => mapping(address spender => uint256)) public _allowances;
    mapping(uint256 batchId => mapping(address owner => uint256)) public _rewards;
    mapping(uint256 batchId => uint256) private _totalSupply;

    uint256 public lastEpochTimestamp;
    uint256 public epochDuration = 1 days;
    uint256 public epochReward;

    uint256 public batchVestingDuration;

    mapping(uint256 batchId => uint256) public batchVestingDurations;

    address public controller;

    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init();
    }

    /* ========== ERC-20 FUNCTIONS ========== */

    function totalSupply() public view override returns (uint256) {
        return _totalSupply[currentBatchId];
    }

    function balanceOf(address _account) public view override returns (uint256) {
        return _balances[currentBatchId][_account];
    }

    function transfer(address _to, uint256 _amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, _to, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) public view virtual override returns (uint256) {
        return _allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, _spender, _amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address _spender, uint256 _addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, _spender, allowance(owner, _spender) + _addedValue);
        return true;
    }

    function decreaseAllowance(address _spender, uint256 _subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, _spender);
        require(currentAllowance >= _subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, _spender, currentAllowance - _subtractedValue);
        }

        return true;
    }

    function mint(address _to, uint256 _amount) external {
        require(_msgSender() == minter, "LyLevel: !minter");
        _mint(_to, _amount);
    }

    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) public virtual {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    function _transfer(address _from, address _to, uint256 _amount) internal {
        require(_from != address(0), "ERC20: transfer from the zero address");
        require(_to != address(0), "ERC20: transfer to the zero address");

        uint256 fromBalance = _balances[currentBatchId][_from];
        require(fromBalance >= _amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[currentBatchId][_from] = fromBalance - _amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[currentBatchId][_to] += _amount;
        }

        emit Transfer(_from, _to, _amount);
    }

    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "ERC20: mint to the zero address");

        _totalSupply[currentBatchId] += _amount;
        unchecked {
            // Overflow not possible: balance + _amount is at most totalSupply + _amount, which is checked above.
            _balances[currentBatchId][_account] += _amount;
        }
        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[currentBatchId][_account];
        require(accountBalance >= _amount, "ERC20: burn _amount exceeds balance");
        unchecked {
            _balances[currentBatchId][_account] = accountBalance - _amount;
            // Overflow not possible: _amount <= accountBalance <= totalSupply.
            _totalSupply[currentBatchId] -= _amount;
        }

        emit Transfer(_account, address(0), _amount);
    }

    function _approve(address _owner, address _spender, uint256 _amount) internal virtual {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(_spender != address(0), "ERC20: approve to the zero address");

        _allowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    function _spendAllowance(address _owner, address _spender, uint256 _amount) internal virtual {
        uint256 currentAllowance = allowance(_owner, _spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= _amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(_owner, _spender, currentAllowance - _amount);
            }
        }
    }

    /* ========== LOYALTY REWARDING FUNCTIONS ========== */

    function getNextBatch()
        public
        view
        returns (uint256 _nextEpochTimestamp, uint256 _nextEpochReward, uint256 _vestingDuration)
    {
        _nextEpochTimestamp = lastEpochTimestamp + epochDuration;
        _nextEpochReward = epochReward;
        _vestingDuration = batchVestingDuration;
    }

    function claimable(uint256 _batchId, address _account) public view returns (uint256) {
        if (_batchId > currentBatchId) {
            return 0;
        } else {
            uint256 reward = _balances[_batchId][_account] * batches[_batchId].rewardPerShare / PRECISION;
            uint256 vestingDuration = batchVestingDurations[_batchId];
            if (vestingDuration != 0) {
                BatchInfo memory batch = batches[_batchId];
                uint256 duration = block.timestamp >= (batch.allocatedTime + vestingDuration)
                    ? vestingDuration
                    : (block.timestamp - batch.allocatedTime);
                reward = reward * duration / vestingDuration;
            }
            return reward > _rewards[_batchId][_account] ? reward - _rewards[_batchId][_account] : 0;
        }
    }

    function claimRewards(uint256 _batchId, address _receiver) public {
        address sender = _msgSender();
        uint256 amount = claimable(_batchId, sender);
        require(amount > 0, "LyLevel: nothing to claim");
        _rewards[_batchId][sender] += amount;
        rewardToken.safeTransfer(_receiver, amount);
        emit Claimed(sender, _batchId, amount, _receiver);
    }

    function claimMultiple(uint256[] calldata _epochs, address _to) external {
        uint256 _totalClaimableRewards = 0;
        address _sender = _msgSender();
        for (uint256 i = 0; i < _epochs.length;) {
            uint256 _batchId = _epochs[i];
            uint256 _amount = claimable(_batchId, _sender);
            if (_amount > 0) {
                _totalClaimableRewards += _amount;
                _rewards[_batchId][_sender] += _amount;
                emit Claimed(_sender, _batchId, _amount, _to);
            }

            unchecked {
                ++i;
            }
        }
        if (_totalClaimableRewards > 0) {
            rewardToken.safeTransfer(_to, _totalClaimableRewards);
        }
    }

    /* ========== RESTRICTIVE FUNCTIONS ========== */

    function setBatchVestingDuration(uint256 _duration) external onlyOwner {
        require(_duration <= MAX_BATCH_VESTING_DURATION, "Must <= MAX_BATCH_VESTING_DURATION");
        batchVestingDuration = _duration;
        emit BatchVestingDurationSet(_duration);
    }

    function setMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "LyLevel: zero address");
        minter = _minter;
        emit MinterSet(_minter);
    }

    function setEpoch(uint256 _epochDuration) public onlyOwner {
        require(_epochDuration >= MIN_EPOCH_DURATION, "Must >= MIN_EPOCH_DURATION");
        epochDuration = _epochDuration;
        emit EpochSetV2(epochDuration);
    }

    function setController(address _controller) external onlyOwner {
        require(_controller != address(0), "Invalid address");
        controller = _controller;
        emit ControllerSet(_controller);
    }

    function withdrawLVL(address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid address");
        rewardToken.safeTransfer(_to, _amount);
        emit LVLWithdrawn(_to, _amount);
    }

    function addReward(uint256 _rewardAmount) external {
        require(msg.sender == controller, "!Controller");
        require(_rewardAmount > 0, "Reward = 0");
        rewardToken.safeTransferFrom(msg.sender, address(this), _rewardAmount);
        epochReward += _rewardAmount;
        emit RewardAdded(currentBatchId, _rewardAmount, msg.sender);
    }

    function allocate() external {
        (uint256 _epochTimestamp, uint256 _rewardAmount, uint256 _vestingDuration) = getNextBatch();
        require(block.timestamp >= _epochTimestamp, "now < trigger_time");
        require(_rewardAmount > 0, "Reward = 0");
        BatchInfo memory newBatch = BatchInfo({
            totalBalance: totalSupply(),
            rewardPerShare: _rewardAmount * PRECISION / totalSupply(),
            allocatedTime: block.timestamp
        });
        batches[currentBatchId] = newBatch;
        batchVestingDurations[currentBatchId] = _vestingDuration;
        epochReward = 0;
        emit RewardAllocated(currentBatchId, _rewardAmount);

        currentBatchId++;
        lastEpochTimestamp = _epochTimestamp;
        emit BatchStarted(currentBatchId);
    }

    /* ========== EVENT ========== */
    event MinterSet(address minter);
    event EpochSetV2(uint256 epochDuration);
    event Claimed(address indexed user, uint256 indexed batchId, uint256 amount, address to);
    event RewardAllocated(uint256 indexed batchId, uint256 amount);
    event BatchStarted(uint256 id);
    event BatchVestingDurationSet(uint256 duration);
    event RewardAdded(uint256 _batchId, uint256 _rewardTokens, address _from);
    event LVLWithdrawn(address _to, uint256 _amount);
    event ControllerSet(address _controller);
}

