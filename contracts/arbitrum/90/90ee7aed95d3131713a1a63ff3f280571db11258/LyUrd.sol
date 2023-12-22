// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.17;

import { IERC20 } from "./IERC20.sol";
import { Initializable } from "./Initializable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

contract LyUrd is Initializable, OwnableUpgradeable, IERC20 {
    struct RedeemProgramInfo {
        uint256 rewardPerShare;
        uint256 totalBalance;
        uint256 allocatedTime;
    }

    string public constant name = "UrDex loyalty token";

    string public constant symbol = "Url";

    uint256 public constant decimals = 18;

    uint256 public constant PRECISION = 1e6;

    address public minter;

    IERC20 public rewardToken;

    uint256 public currentBatchId;

    mapping(uint256 => RedeemProgramInfo) public redeemPrograms;

    mapping(uint256 => mapping(address => uint256)) public userBalance;

    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(uint256 => mapping(address => uint256)) public userClaimed;

    mapping(uint256 => uint256) private totalSupply_;

    uint256 public totalUnclaimReward;

    uint256 public rewardsPerEpoch;

    address public controller;

    uint256 public constant MAX_BATCH_VESTING_DURATION = 7 days;
    uint256 public batchVestingDuration;
    mapping(uint256 => uint256) public batchVestingDurations;

    function initialize() external initializer {
        __Ownable_init();
    }

    /* ========== VIEW FUNCTIONS ========== */
    function totalSupply() public view override returns (uint256) {
        return totalSupply_[currentBatchId];
    }

    function balanceOf(address _account) public view override returns (uint256) {
        return userBalance[currentBatchId][_account];
    }

    function claimable(uint256 _batchId, address _account) public view returns (uint256) {
        if (_batchId > currentBatchId) {
            return 0;
        } else {
            uint256 reward = (userBalance[_batchId][_account] * redeemPrograms[_batchId].rewardPerShare) / PRECISION;
            uint256 vestingDuration = batchVestingDurations[_batchId];

            if (vestingDuration != 0) {
                RedeemProgramInfo memory info = redeemPrograms[_batchId];
                uint256 duration = block.timestamp >= (info.allocatedTime + vestingDuration) ? vestingDuration : (block.timestamp - info.allocatedTime);
                reward = (reward * duration) / vestingDuration;
            }

            return reward > userClaimed[_batchId][_account] ? reward - userClaimed[_batchId][_account] : 0;
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

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
        require(_msgSender() == minter, "LyUr: !minter");
        _mint(_to, _amount);
    }

    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) public virtual {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    function claim(uint256 _batchId, address _receiver) external {
        require(rewardToken != IERC20(address(0)), "LyUr: reward token not set");
        address sender = _msgSender();
        uint256 amount = claimable(_batchId, sender);
        require(amount != 0, "LyUr: nothing to claim");
        userClaimed[_batchId][sender] += amount;
        totalUnclaimReward -= amount;
        _safeTransferReward(_receiver, amount);
        emit Claimed(sender, _batchId, amount, _receiver);
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    function _transfer(address _from, address _to, uint256 _amount) internal {
        require(_from != address(0), "ERC20: transfer from the zero address");
        require(_to != address(0), "ERC20: transfer to the zero address");

        uint256 fromBalance = userBalance[currentBatchId][_from];
        require(fromBalance >= _amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            userBalance[currentBatchId][_from] = fromBalance - _amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            userBalance[currentBatchId][_to] += _amount;
        }

        emit Transfer(_from, _to, _amount);
    }

    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "ERC20: mint to the zero address");

        totalSupply_[currentBatchId] += _amount;
        unchecked {
            // Overflow not possible: balance + _amount is at most totalSupply + _amount, which is checked above.
            userBalance[currentBatchId][_account] += _amount;
        }
        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = userBalance[currentBatchId][_account];
        require(accountBalance >= _amount, "ERC20: burn _amount exceeds balance");
        unchecked {
            userBalance[currentBatchId][_account] = accountBalance - _amount;
            // Overflow not possible: _amount <= accountBalance <= totalSupply.
            totalSupply_[currentBatchId] -= _amount;
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

    // Safe reward transfer function, just in case if rounding error causes pool to not have enough reward.
    function _safeTransferReward(address _to, uint256 _amount) internal {
        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        if (_amount > rewardBalance) {
            rewardToken.transfer(_to, rewardBalance);
        } else {
            rewardToken.transfer(_to, _amount);
        }
    }

    /* ========== RESTRICTIVE FUNCTIONS ========== */
    function setRewardToken(address _rewardToken) external onlyOwner {
        require(rewardToken == IERC20(address(0)), "LyUr: reward token already set");
        rewardToken = IERC20(_rewardToken);
        emit RewardTokenSet(_rewardToken);
    }

    function setMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "LyUr: zero address");
        minter = _minter;
        emit MinterSet(_minter);
    }

    function setRewardsPerEpoch(uint256 _rewardsPerEpoch) external onlyOwner {
        require(_rewardsPerEpoch > 0, "LyUr: RewardsPerEpoch > 0");
        rewardsPerEpoch = _rewardsPerEpoch;
        emit RewardsPerEpochUpdate(_rewardsPerEpoch);
    }

    function setController(address _controller) external onlyOwner {
        require(_controller != address(0), "LyUr: zero address");
        controller = _controller;
        emit ControllerUpdate(_controller);
    }

    function setBatchVestingDuration(uint256 _duration) external onlyOwner {
        require(_duration <= MAX_BATCH_VESTING_DURATION, "Must <= MAX_BATCH_VESTING_DURATION");
        batchVestingDuration = _duration;
        emit BatchVestingDurationSet(_duration);
    }

    /// @notice allocate reward for current batch and start a new batch
    function allocateReward() external {
        require(msg.sender == controller, "LyUr: only controller");
        require(rewardToken != IERC20(address(0)), "LyUr: reward token not set");
        require(totalSupply() > 0, "LyUr: no supply");
        require(totalUnclaimReward + rewardsPerEpoch <= rewardToken.balanceOf(address(this)), "LyUr: insufficient reward balance");
        RedeemProgramInfo memory info = RedeemProgramInfo({
            totalBalance: totalSupply(),
            rewardPerShare: (rewardsPerEpoch * PRECISION) / totalSupply(),
            allocatedTime: block.timestamp
        });
        batchVestingDurations[currentBatchId] = batchVestingDuration;
        totalUnclaimReward += rewardsPerEpoch;
        redeemPrograms[currentBatchId] = info;
        emit RewardAllocated(currentBatchId, rewardsPerEpoch);
        currentBatchId++;
        emit BatchStarted(currentBatchId);
    }

    /* ========== EVENT ========== */
    event MinterSet(address minter);
    event Claimed(address indexed user, uint256 indexed batchId, uint256 amount, address to);
    event RewardAllocated(uint256 indexed batchId, uint256 amount);
    event BatchStarted(uint256 id);
    event RewardTokenSet(address token);
    event RewardsPerEpochUpdate(uint256);
    event ControllerUpdate(address);
    event BatchVestingDurationSet(uint256 duration);
}

