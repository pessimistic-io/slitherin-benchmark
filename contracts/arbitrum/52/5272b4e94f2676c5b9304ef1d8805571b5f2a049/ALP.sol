/**
 * https://arcadeum.io
 * https://arcadeum.gitbook.io/arcadeum
 * https://twitter.com/arcadeum_io
 * https://discord.gg/qBbJ2hNPf8
 */

// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

import "./IALP.sol";
import "./ERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20BackwardsCompatible.sol";
import "./IFeeTracker.sol";
import "./IesARCIncentiveManager.sol";

contract ALP is IALP, ERC20, Ownable, ReentrancyGuard {
    error PoolNotPublic();
    error PoolAlreadyPublic();
    error InsufficientUSDBalance(uint256 _amountUSDT, uint256 _balance);
    error InsufficientUSDAllowance(uint256 _amountUSDT, uint256 _allowance);
    error InsufficientALPBalance(uint256 _amountALP, uint256 _balance);
    error InsufficientALPAllowance(uint256 _amountALP, uint256 _allowance);
    error ZeroDepositAmount();
    error ZeroWithdrawalAmount();
    error OnlyHouse(address _caller);
    error AlreadyInitialized();
    error NotInitialized();
    error DepositFeeTooHigh();
    error WithdrawFeeTooHigh();
    error FeesRemoved();

    IERC20BackwardsCompatible public immutable usdt;

    uint256 public depositFee = 100;
    uint256 public withdrawFee = 100;
    bool public feesRemoved;
    IFeeTracker public sarcFees;
    IFeeTracker public xarcFees;
    IFeeTracker public esarcFees;
    IesARCIncentiveManager public esarcIncentiveManager;

    mapping (address => uint256) public depositsByAccount;
    mapping (address => uint256) public withdrawalsByAccount;
    uint256 public deposits;
    uint256 public withdrawals;
    uint256 public inflow;
    uint256 public outflow;
    uint256 public depositFeesCollected;
    uint256 public withdrawalFeesCollected;

    address public house;

    event Deposit(address indexed _account, uint256 indexed _amountUSDT, uint256 indexed _timestamp, uint256 _amountALP, uint256 _fee);
    event Withdrawal(address indexed _account, uint256 indexed _amountUSDT, uint256 indexed _timestamp, uint256 _amountALP, uint256 _fee);
    event Win(address indexed _account, uint256 indexed _game, uint256 indexed _timestamp, bytes32 _requestId, uint256 _amount);
    event Loss(address indexed _account, uint256 indexed _game, uint256 indexed _timestamp, bytes32 _requestId, uint256 _amount);

    mapping (address => bool) public depositorWhitelist;
    bool public open;

    bool private initialized;

    modifier onlyHouse() {
        if (msg.sender != house) {
            revert OnlyHouse(msg.sender);
        }
        _;
    }

    constructor(address _USDT) ERC20("Arcadeum LP", "ALP") {
        usdt = IERC20BackwardsCompatible(_USDT);
    }

    function initialize(address _house, address _sARCFees, address _xARCFees, address _esARCFees) external nonReentrant onlyOwner {
        if (initialized) {
            revert AlreadyInitialized();
        }
        house = _house;
        sarcFees = IFeeTracker(_sARCFees);
        xarcFees = IFeeTracker(_xARCFees);
        esarcFees = IFeeTracker(_esARCFees);
        usdt.approve(_sARCFees, type(uint256).max);
        usdt.approve(_xARCFees, type(uint256).max);
        usdt.approve(_esARCFees, type(uint256).max);
        initialized = true;
    }

    function deposit(uint256 _amountUSDT) external nonReentrant {
        if (!open && !depositorWhitelist[msg.sender]) {
            revert PoolNotPublic();
        }
        if (_amountUSDT == 0) {
            revert ZeroDepositAmount();
        }
        if (_amountUSDT > usdt.balanceOf(msg.sender)) {
            revert InsufficientUSDBalance(_amountUSDT, usdt.balanceOf(msg.sender));
        }
        if (_amountUSDT > usdt.allowance(msg.sender, address(this))) {
            revert InsufficientUSDAllowance(_amountUSDT, usdt.balanceOf(msg.sender));
        }

        uint256 _fee;
        if (depositFee > 0) {
            // some accounts have different fees
            _fee = _amountUSDT * depositFee / 10000;
            usdt.transferFrom(msg.sender, address(this), _fee);
            _depositYield(0, _fee);
            _amountUSDT -= _fee;
            depositFeesCollected += _fee;
        }

        uint256 _supplyALP = this.totalSupply();
        uint256 _amountALP = _supplyALP == 0 ? _amountUSDT : (_amountUSDT * _supplyALP) / usdt.balanceOf(address(this));

        _mint(msg.sender, _amountALP);
        usdt.transferFrom(msg.sender, address(this), _amountUSDT);
        deposits += _amountUSDT;
        depositsByAccount[msg.sender] += _amountUSDT;
        try esarcIncentiveManager.registerALPDeposit(msg.sender, _amountUSDT, block.timestamp, _amountALP) {} catch {}
        emit Deposit(msg.sender, _amountUSDT, block.timestamp, _amountALP, _fee);
    }

    function withdraw(uint256 _amountALP) external nonReentrant {
        if (_amountALP == 0) {
            revert ZeroWithdrawalAmount();
        }
        if (_amountALP > this.balanceOf(msg.sender)) {
            revert InsufficientALPBalance(_amountALP, this.balanceOf(msg.sender));
        }
        if (_amountALP > this.allowance(msg.sender, address(this))) {
            revert InsufficientALPAllowance(_amountALP, this.balanceOf(msg.sender));
        }

        uint256 _amountUSDT = (_amountALP * usdt.balanceOf(address(this))) / this.totalSupply();

        uint256 _fee;
        if (withdrawFee > 0) {
            // some accounts have different fees
            _fee = _amountUSDT * withdrawFee / 10000;
            _depositYield(1, _fee);
            _amountUSDT -= _fee;
            withdrawalFeesCollected += _fee;
        }

        _burn(msg.sender, _amountALP);
        usdt.transfer(msg.sender, _amountUSDT);
        withdrawals += _amountUSDT;
        withdrawalsByAccount[msg.sender] += _amountUSDT;
        try esarcIncentiveManager.registerALPWithdrawal(msg.sender, _amountUSDT, block.timestamp, _amountALP) {} catch {}
        emit Withdrawal(msg.sender, _amountUSDT, block.timestamp, _amountALP, _fee);
    }

    function _depositYield(uint256 _source, uint256 _fee) private {
        xarcFees.depositYield(_source, _fee * 7000 / 10000);
        uint256 _fee15Pct = _fee * 1500 / 10000;
        sarcFees.depositYield(_source, _fee15Pct);
        esarcFees.depositYield(_source, _fee15Pct);
    }

    function payWin(address _account, uint256 _game, bytes32 _requestId, uint256 _amount) external override nonReentrant onlyHouse {
        usdt.transfer(_account, _amount);
        outflow += _amount;
        emit Win(_account, _game, block.timestamp, _requestId, _amount);
    }

    function receiveLoss(address _account, uint256 _game, bytes32 _requestId, uint256 _amount) external override nonReentrant onlyHouse {
        usdt.transferFrom(msg.sender, address(this), _amount);
        inflow += _amount;
        emit Loss(_account, _game, block.timestamp, _requestId, _amount);
    }

    function setDepositFee(uint256 _depositFee) external nonReentrant onlyOwner {
        if (feesRemoved) {
            revert FeesRemoved();
        }
        if (_depositFee > 100) {
            revert DepositFeeTooHigh();
        }
        depositFee = _depositFee;
    }

    function setWithdrawFee(uint256 _withdrawFee) external nonReentrant onlyOwner {
        if (feesRemoved) {
            revert FeesRemoved();
        }
        if (_withdrawFee > 100) {
            revert WithdrawFeeTooHigh();
        }
        withdrawFee = _withdrawFee;
    }

    function removeFees() external nonReentrant onlyOwner {
        if (feesRemoved) {
            revert FeesRemoved();
        }
        depositFee = 0;
        withdrawFee = 0;
        feesRemoved = true;
    }

    function setDepositorWhitelist(address _depositor, bool _isWhitelisted) external nonReentrant onlyOwner {
        depositorWhitelist[_depositor] = _isWhitelisted;
    }

    function setEsARCIncentiveManager(address _esarcIncentiveManager) external nonReentrant onlyOwner {
        esarcIncentiveManager = IesARCIncentiveManager(_esarcIncentiveManager);
    }

    function goPublic() external nonReentrant onlyOwner {
        if (open) {
            revert PoolAlreadyPublic();
        }
        open = true;
    }

    function getALPFromUSDT(uint256 _amountUSDT) external view returns (uint256) {
        uint256 _supplyALP = this.totalSupply();
        return _supplyALP == 0 ? _amountUSDT : (_amountUSDT * _supplyALP) / usdt.balanceOf(address(this));
    }

    function getUSDTFromALP(uint256 _amountALP) external view returns (uint256) {
        return (_amountALP * usdt.balanceOf(address(this))) / this.totalSupply();
    }

    function getDepositsByAccount(address _account) external view returns (uint256) {
        return depositsByAccount[_account];
    }

    function getWithdrawalsByAccount(address _account) external view returns (uint256) {
        return withdrawalsByAccount[_account];
    }

    function getDeposits() external view returns (uint256) {
        return deposits;
    }

    function getWithdrawals() external view returns (uint256) {
        return withdrawals;
    }

    function getInflow() external view returns (uint256) {
        return inflow;
    }

    function getOutflow() external view returns (uint256) {
        return outflow;
    }

    function getFees() external view returns (uint256, uint256) {
        return (depositFee, withdrawFee);
    }

    function getFeesCollected() external view returns (uint256, uint256, uint256) {
        return (depositFeesCollected + withdrawalFeesCollected, depositFeesCollected, withdrawalFeesCollected);
    }

    function getEsARCIncentiveManager() external view returns (address) {
        return address(esarcIncentiveManager);
    }

    function getOpen() external view returns (bool) {
        return open;
    }

    receive() external payable {}
}

