//SPDX-License-Identifier: Unlicense
pragma solidity = 0.8.17;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IALP.sol";

/// @notice StablzALPIntegration
contract StablzALPIntegration is ReentrancyGuard, Ownable {

    using SafeERC20 for IERC20;

    IERC20 public immutable usdt;
    IALP public immutable alp;
    /// @dev metrics
    uint public totalDeposited;
    uint public totalWithdrawn;
    uint public totalClaimedRewards;
    uint public totalFee;
    uint public yieldFee = 2000;
    bool public isDepositingEnabled;
    address public immutable feeHandler;
    address private constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address private constant ALP = 0x875Ce69F87beB1d9B0c407597d4057Fa91D364A7;
    uint private constant MAX_YIELD_FEE = 2000;
    /// @dev FEE_DENOMINATOR is used for yieldFee as well as ALP's fees
    uint private constant FEE_DENOMINATOR = 10000;

    struct User {
        uint lp;
        uint staked;
    }

    mapping(address => User) private _users;

    event DepositingEnabled();
    event DepositingDisabled();
    event YieldFeeUpdated(uint yieldFee);
    event Deposit(address indexed user, uint usdt, uint lp);
    event Withdraw(address indexed user, uint lp, uint stake, uint rewards, uint fee);

    /// @param _feeHandler Fee handler
    constructor(address _feeHandler) {
        require(_feeHandler != address(0), "StablzALPIntegration: _feeHandler cannot be the zero address");
        feeHandler = _feeHandler;
        usdt = IERC20(USDT);
        alp = IALP(ALP);
    }

    /// @notice Enable depositing (owner)
    function enableDepositing() external onlyOwner {
        require(!isDepositingEnabled, "StablzALPIntegration: Depositing is already enabled");
        isDepositingEnabled = true;
        emit DepositingEnabled();
    }

    /// @notice Disable depositing (owner)
    function disableDepositing() external onlyOwner {
        require(isDepositingEnabled, "StablzALPIntegration: Depositing is already disabled");
        isDepositingEnabled = false;
        emit DepositingDisabled();
    }

    /// @notice Set yield fee (owner)
    /// @param _yieldFee Yield fee percent to 2 d.p. precision e.g. 20% = 2000
    function setYieldFee(uint _yieldFee) external onlyOwner {
        require(_yieldFee <= MAX_YIELD_FEE, "StablzALPIntegration: _yieldFee cannot exceed 20% (2000)");
        yieldFee = _yieldFee;
        emit YieldFeeUpdated(_yieldFee);
    }

    /// @notice Deposit USDT into the Arcadeum LP pool
    /// @param _amount USDT amount to deposit
    /// @param _minLP Minimum expected LP
    function deposit(uint _amount, uint _minLP) external nonReentrant {
        address user = _msgSender();
        require(0 < _amount, "StablzALPIntegration: _amount must be greater than zero");
        require(0 < _minLP, "StablzALPIntegration: _minLP must be greater than zero");
        require(isDepositingAvailable(), "StablzALPIntegration: Depositing is not available at this time");
        require(_amount <= usdt.balanceOf(user), "StablzALPIntegration: Insufficient balance");
        require(_amount <= usdt.allowance(user, address(this)), "StablzALPIntegration: Insufficient allowance");
        uint received = _deposit(_amount, _minLP);
        _users[user].staked += _amount;
        _users[user].lp += received;
        totalDeposited += _amount;
        emit Deposit(user, _amount, received);
    }

    /// @notice Withdraw USDT from the Arcadeum LP pool
    /// @param _lp LP amount to withdraw
    /// @param _minUSDT Minimum expected USDT
    function withdraw(uint _lp, uint _minUSDT) external nonReentrant {
        address user = _msgSender();
        uint total = _users[user].lp;
        require(0 < _lp && _lp <= total, "StablzALPIntegration: _lp must be greater than 0 and less than or equal to the total");
        require(0 < _minUSDT, "StablzALPIntegration: _minUSDT must be greater than zero");
        _users[user].lp -= _lp;
        uint totalUSDT = calculateUSDTForLP(total);
        uint received = _withdraw(_lp, _minUSDT);
        uint staked = _users[user].staked;
        (uint stake, uint rewards, uint fee) = _calculateWithdrawal(received, staked, totalUSDT);
        _reduceStake(user, stake);
        totalWithdrawn += stake;
        totalClaimedRewards += rewards;
        if (0 < fee) {
            totalFee += fee;
            usdt.safeTransfer(feeHandler, fee);
        }
        usdt.safeTransfer(user, stake + rewards);
        emit Withdraw(user, _lp, stake, rewards, fee);
    }

    /// @notice Get user details
    /// @param _user User
    /// @return user LP amount, USDT stake
    function getUser(address _user) external view returns (User memory user) {
        require(_user != address(0), "StablzALPIntegration: _user cannot be the zero address");
        return _users[_user];
    }

    /// @notice Calculate the LP minted for _usdtAmount
    /// @param _usdtAmount USDT amount to deposit
    function calculateLPForUSDT(uint _usdtAmount) external view returns (uint amount) {
        amount = _usdtAmount;
        /// @dev take off ALP fee from _usdtAmount
        uint depositFee = alp.depositFee();
        if (depositFee > 0) {
            amount -= _usdtAmount * depositFee / FEE_DENOMINATOR;
        }
        return alp.getALPFromUSDT(amount);
    }

    /// @notice Calculate the USDT withdrawn for burning _lpAmount
    /// @param _lpAmount LP amount to withdraw
    /// @return amount USDT amount
    function calculateUSDTForLP(uint _lpAmount) public view returns (uint amount) {
        amount = alp.getUSDTFromALP(_lpAmount);
        /// @dev take off ALP fee from amount
        uint withdrawFee = alp.withdrawFee();
        if (withdrawFee > 0) {
            amount -= amount * withdrawFee / FEE_DENOMINATOR;
        }
        return amount;
    }

    /// @notice Is depositing available
    /// @return isAvailable true - available, false - unavailable
    function isDepositingAvailable() public view returns (bool isAvailable) {
        return isDepositingEnabled && _isAlpDepositAvailable();
    }

    /// @dev Deposits USDT into ALP, checks if _minLP is met
    /// @param _amount USDT amount to deposit
    /// @param _minLP Minimum expected LP
    /// @return received LP received
    function _deposit(uint _amount, uint _minLP) internal returns (uint received) {
        usdt.safeTransferFrom(_msgSender(), address(this), _amount);
        usdt.safeApprove(ALP, _amount);
        uint lpBefore = IERC20(ALP).balanceOf(address(this));
        alp.deposit(_amount);
        uint lpAfter = IERC20(ALP).balanceOf(address(this));
        received = lpAfter - lpBefore;
        require(received >= _minLP, "StablzALPIntegration: LP received is less than the minimum expected");
        return received;
    }

    /// @dev Withdraws USDT from ALP, checks if _minUSDT is met
    /// @param _lp LP amount to withdraw
    /// @param _minUSDT Minimum expected USDT
    /// @return received USDT received
    function _withdraw(uint _lp, uint _minUSDT) internal returns (uint received) {
        uint usdtBefore = usdt.balanceOf(address(this));
        IERC20(ALP).safeIncreaseAllowance(ALP, _lp);
        alp.withdraw(_lp);
        /// @dev ALP requires sufficient allowance but doesn't spend it, so decrease it here afterwards
        IERC20(ALP).safeDecreaseAllowance(ALP, _lp);
        uint usdtAfter = usdt.balanceOf(address(this));
        received = usdtAfter - usdtBefore;
        require(_minUSDT <= received, "StablzALPIntegration: USDT received is less than the minimum expected");
        return received;
    }

    /// @dev Reduce stake
    /// @param _user User
    /// @param _amount Amount to reduce _user stake by
    function _reduceStake(address _user, uint _amount) internal {
        if (_amount <= _users[_user].staked) {
            _users[_user].staked -= _amount;
        } else {
            /// @dev safeguard
            _users[_user].staked = 0;
        }
    }

    /// @dev Calculate the components of a withdrawal
    /// @param _received USDT received from withdrawing
    /// @param _staked Staked amount
    /// @param _total Total value of LP in USDT
    /// @return stake Stake
    /// @return rewards Rewards
    /// @return fee Fee
    function _calculateWithdrawal(uint _received, uint _staked, uint _total) internal view returns (uint stake, uint rewards, uint fee) {
        if (_staked <= _total) {
            /// @dev in profit
            uint profit = _total - _staked;
            rewards = _received * profit / _total;
            stake = _received - rewards;
            if (0 < rewards && 0 < yieldFee) {
                fee = rewards * yieldFee / FEE_DENOMINATOR;
                rewards -= fee;
            }
        } else {
            /// @dev at loss
            stake = _received;
        }
        return (stake, rewards, fee);
    }

    /// @dev Checks if ALP allows depositing either because of the address being whitelisted or if it is open
    /// @return bool true - Available, false - Not available
    function _isAlpDepositAvailable() internal view returns (bool) {
        return alp.depositorWhitelist(address(this)) || alp.open();
    }
}

