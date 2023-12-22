// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.2;

import { EnumerableSet} from "./EnumerableSet.sol";
import { Strings} from "./Strings.sol";
import { VeGnome } from "./VeGnome.sol";
import { IERC20 } from "./IERC20.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
// import "hardhat/console.sol";

contract VeGnomeLockWrapper is ReentrancyGuardUpgradeable, OwnableUpgradeable {
    event Transfer(address indexed from, address indexed to, uint256 value);

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    IERC20 public lockToken;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function initialized(address _lockToken, string memory _nameArg, string memory _symbolArg) internal {
        lockToken = IERC20(_lockToken);
        name = _nameArg;
        symbol = _symbolArg;
    }

    function totalSupply() public view returns (uint256) { return _totalSupply; }
    function balanceOf(address _account) public view returns (uint256) { return _balances[_account]; }

    function _lock(address _beneficiary, uint256 _amount) internal virtual nonReentrant {
        require(_msgSender() == _beneficiary, "Address does not match");
        require(_amount > 0, "Cannot lock 0");
        _totalSupply = _totalSupply + _amount;
        _balances[_beneficiary] = _balances[_beneficiary] + _amount;
        lockToken.transferFrom(_beneficiary, address(this), _amount);
        emit Transfer(address(0), _beneficiary, _amount);
    }

    function _unlock(uint256 _amt) internal nonReentrant {
        uint256 _amount = _amt > 0 ? _amt : _balances[_msgSender()];
        require(_amount > 0, "Nothing to unlock");
        _totalSupply = _totalSupply - _balances[_msgSender()]; // Remove all from balances
        _balances[_msgSender()] = 0;
        lockToken.transfer(_msgSender(), _amount);
        emit Transfer(_msgSender(), address(0), _amount);
    }
}

contract VeGnomeLock is VeGnomeLockWrapper { 
    using Strings for uint256;

    uint public lastPauseTime;
    bool public paused;
    bool public initializedFlag;

    struct LockEntry { // struct for saving each lock entry
        uint256 vpower;
        uint256 end;
        uint256 ldays;
    }

    // veGNOME
    address public veToken;

    /// @notice length of each lock period in seconds. 7 days = 604,800; 3 months = 7,862,400
    uint256 public MINDAYS;
    uint256 public MAXDAYS;

    uint256 public MAXTIME;
    uint256 public MAX_WITHDRAWAL_PENALTY;
    uint256 public PRECISION;

    uint256 FULL_SCALE;
    uint256 public minLockedAmount;
    uint256 public earlyWithdrawPenaltyRate;

    uint256 public avgLockPeriod;
    uint256 public numLockEntries;

    uint256 public totalVeGnome;
    
    mapping(address => LockEntry) public lockEntries;

    /* =============== EVENTS ==================== */
    event Lock(address indexed provider, uint256 value, uint256 locktime, uint256 timestamp);
    event Unlock(address indexed provider, uint256 value, uint256 timestamp);
    event Recovered(address token, uint256 amount);
    event EarlyWithdrawPenaltySet(uint256 indexed penalty);
    event MinLockedAmountSet(uint256 indexed amount);

    function initialize(
        string memory _name,
        string memory _symbol,
        address _lockToken,
        address _veToken,
        uint256 _minLockedAmount
    ) public initializer {
        require(!initializedFlag, "Contract is already initialized");
        __Ownable_init();
        VeGnomeLockWrapper.initialized(
            _lockToken,
            _name,
            _symbol
        );
        veToken = _veToken;
        FULL_SCALE = 1e18;
        MINDAYS = 7;
        MAXDAYS = 4 * 365;
        MAXTIME = MAXDAYS * 1 days; // 4 years
        earlyWithdrawPenaltyRate = 30000; // 30%
        MAX_WITHDRAWAL_PENALTY = 50000; // 50%
        PRECISION = 100000;
        minLockedAmount = _minLockedAmount;
        initializedFlag = true;
    }
    
    function lock(uint256 _amount, uint256 _days) external {
        require(_amount >= minLockedAmount, "Less than min amount");
        require(balanceOf(_msgSender()) == 0, "Withdraw old tokens first");
        require(_days >= MINDAYS, "Voting lock can be 7 days min");
        require(_days <= MAXDAYS, "Voting lock can be 4 years max");
        numLockEntries += 1;
        _lock_for(_msgSender(), _amount, _days);
    }
    
    function lock(uint256 _amount) external {
        require(_amount >= minLockedAmount, "Less than min amount");
        _lock_for(_msgSender(), _amount, 0);
    }

    function increase_unlock_time(uint256 _days) external {
        require(_days >= MINDAYS, "Voting lock can be 7 days min");
        require(_days <= MAXDAYS, "Voting lock can be 4 years max");
        _lock_for(_msgSender(), 0, _days);
    }

    function unlock() external {        
        LockEntry storage _locked = lockEntries[_msgSender()];
        uint256 _now = block.timestamp;
        uint256 _amount = balanceOf(_msgSender());
        require(_now >= _locked.end, "The lock didn't expire");
        VeGnome(veToken).burn(_msgSender(), _locked.vpower);
        avgLockPeriod -= _locked.ldays / numLockEntries;
        totalVeGnome -= _locked.vpower;
        _locked.end = 0;
        _locked.vpower = 0;
        _locked.ldays = 0;
        numLockEntries -= 1;
        _unlock(0);

        emit Unlock(_msgSender(), _amount, _now);
    }
    
    function emergencyUnlock() external {
        LockEntry storage _locked = lockEntries[_msgSender()];
        uint256 _now = block.timestamp;
        uint256 _amount = balanceOf(_msgSender());
        require(_amount > 0, "Nothing to withdraw");
        if (_now < _locked.end) {
            uint256 _fee = (_amount * earlyWithdrawPenaltyRate) / PRECISION;
            _amount = _amount - _fee;
        }
        VeGnome(veToken).burn(_msgSender(), _locked.vpower);
        avgLockPeriod -= _locked.ldays / numLockEntries;
        totalVeGnome -= _locked.vpower;
        _locked.end = 0;
        _locked.vpower = 0;
        _locked.ldays = 0;
        numLockEntries -= 1;
        _unlock(_amount);

        emit Unlock(_msgSender(), _amount, _now);
    }

    function voting_power_unlock_time(uint256 _amount, uint256 _unlockTime) public view returns (uint256) {
        uint256 _now = block.timestamp;
        if (_unlockTime <= _now) return 0;
        uint256 _lockedSeconds = _unlockTime - _now;
        if (_lockedSeconds >= MAXTIME) {
            return _amount;
        }
        return (_amount * _lockedSeconds) / MAXTIME;
    }

    function voting_power_locked_days(uint256 _amount, uint256 _days) public view returns (uint256) {
        if (_days >= MAXDAYS) {
            return _amount;
        }
        return (_amount * _days) / MAXDAYS;
    }

    function _lock_for(
        address _addr,
        uint256 _value,
        uint256 _days
    ) internal {
        LockEntry storage _locked = lockEntries[_addr];
        uint256 _now = block.timestamp;
        uint256 _amount = balanceOf(_addr);
        uint256 _end = _locked.end;
        uint256 _vp;
        if (_amount == 0) {
            _vp = voting_power_locked_days(_value, _days);
            _lock(_addr, _value);
            _locked.end = _now + _days * 1 days;
            _locked.ldays = _days * 1 days;
            avgLockPeriod = (avgLockPeriod * (numLockEntries - 1) + _days * 1 days) / numLockEntries;
        } else if (_days == 0) {
            _vp = voting_power_unlock_time(_value, _end);
            _lock(_addr, _value);
        } else {
            require(_value == 0, "Cannot increase amount and extend lock in the same time");
            _vp = voting_power_locked_days(_amount, _days);
            _locked.end = _end + _days * 1 days;            
            _locked.ldays += _days * 1 days;
            avgLockPeriod += _days * 1 days / numLockEntries;
            require(_locked.end - _now <= MAXTIME, "Cannot extend lock to more than 4 years");
        }
        require(_vp > 0, "No benefit to lock");
        VeGnome(veToken).mint(_addr, _vp);
        _locked.vpower += _vp;
        totalVeGnome += _vp;

        emit Lock(_addr, balanceOf(_addr), _locked.end, _now);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setMinLockedAmount(uint256 _minLockedAmount) external onlyOwner {
        minLockedAmount = _minLockedAmount;
        emit MinLockedAmountSet(_minLockedAmount);
    }

    function setEarlyWithdrawPenaltyRate(uint256 _earlyWithdrawPenaltyRate) external onlyOwner {
        require(_earlyWithdrawPenaltyRate <= MAX_WITHDRAWAL_PENALTY, "withdrawal penalty is too high"); // <= 50%
        earlyWithdrawPenaltyRate = _earlyWithdrawPenaltyRate;
        emit EarlyWithdrawPenaltySet(_earlyWithdrawPenaltyRate);
    }

    function setLockToken(address _locktoken) external onlyOwner {
        lockToken = IERC20(_locktoken);
    }

    function setVeToken(address _vetoken) external onlyOwner {
        veToken = _vetoken;
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address _token, uint256 _amount) external onlyOwner {
        require(_token == veToken, "Cannot withdraw the reward token");
        IERC20(_token).transfer(this.owner(), _amount);
        emit Recovered(_token, _amount);
    }

    function divPrecisely(uint256 x, uint256 y) internal view returns (uint256) {
        // e.g. 8e18 * 1e18 = 8e36
        // e.g. 8e36 / 10e18 = 8e17
        return (x * FULL_SCALE) / y;
    }

    /**
     * @notice Change the paused state of the contract
     * @dev Only the contract owner may call this.
     */
    function setPaused(bool _paused) external onlyOwner {
        // Ensure we're actually changing the state before we do anything
        if (_paused == paused) {
            return;
        }

        // Set our paused state.
        paused = _paused;

        // If applicable, set the last pause time.
        if (paused) {
            lastPauseTime = getTimestamp();
        }

        // Let everyone know that our pause state has changed.
        emit PauseChanged(paused);
    }

    event PauseChanged(bool isPaused);

    modifier notPaused {
        require(!paused, "This action cannot be performed while the contract is paused");
        _;
    }

    function getTimestamp() public view virtual returns (uint256) {
        return block.timestamp;
    }
}

