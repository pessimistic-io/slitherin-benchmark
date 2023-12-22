/*
────────────────────────────────────────────────────────────────────────────
─██████████████─██████──██████─██████████████─██████████████─██████████████─
─██░░░░░░░░░░██─██░░██──██░░██─██░░░░░░░░░░██─██░░░░░░░░░░██─██░░░░░░░░░░██─
─██░░██████████─██░░██──██░░██─██░░██████░░██─██░░██████████─██████░░██████─
─██░░██─────────██░░██──██░░██─██░░██──██░░██─██░░██─────────────██░░██─────
─██░░██─────────██░░██████░░██─██░░██████░░██─██░░██████████─────██░░██─────
─██░░██──██████─██░░░░░░░░░░██─██░░░░░░░░░░██─██░░░░░░░░░░██─────██░░██─────
─██░░██──██░░██─██░░██████░░██─██░░██████░░██─██████████░░██─────██░░██─────
─██░░██──██░░██─██░░██──██░░██─██░░██──██░░██─────────██░░██─────██░░██─────
─██░░██████░░██─██░░██──██░░██─██░░██──██░░██─██████████░░██─────██░░██─────
─██░░░░░░░░░░██─██░░██──██░░██─██░░██──██░░██─██░░░░░░░░░░██─────██░░██─────
─██████████████─██████──██████─██████──██████─██████████████─────██████─────
────────────────────────────────────────────────────────────────────────────
https://ghastprotocol.com/
*/
// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

contract GHALendGND is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public constant xGND = IERC20(0x40EA7f6D6964413D4a26A0a268542DAE9F55768E);
    IERC20 public constant GND = IERC20(0xD67A097dCE9d4474737e6871684aE3c05460F571);

    uint256 public totalDeposits;       // total xGND deposits
    uint256 public totalxDeposits;      // upwards seeking peg
    uint256 public totalBorrows;        // total xGND borrows
    uint256 public totalxBorrows;       // upwards seeking peg
    uint256 public totalNativeDeposits; // total GND deposits

    mapping(address => uint256) public xdeposits;
    mapping(address => uint256) public xborrows;
    mapping(address => uint256) public nativeDeposits;

    // security caps
    uint256 public depositCap       = 10000 * 1e18;
    uint256 public nativeDepositCap = 10000 * 1e18;
    uint256 public borrowCap        = 8000 * 1e18;

    uint256 constant MAX_BPS = 1e4;
    uint256 public LTV       = 0.8 * 1e4;  // can borrow up to 80% LTV
    uint256 public redLTV    = 0.9 * 1e4;  // can be redeemed against above 90% LTV

    uint256 public base   = 2 * 1e16;    // 2%
    uint256 public slope1 = 0.15 * 1e16; // 0.15%
    uint256 public kink   = 80 * 1e16;   // 80%
    uint256 public slope2 = 1.5 * 1e16;  // 1.5%

    uint256 public earnRateSec;
    uint256 public lastUpdate;

    uint256 feeRate = 2500;
    address public treasury = 0x52D16E8550785F3F1073632bC54dAa2e07e60C1c;

    // Ratio to be paid out in esGHA
    uint256 esRatio = 8000;

    IERC20 public constant GHA = IERC20(0xeCA66820ed807c096e1Bd7a1A091cD3D3152cC79);
    IERC20 public constant esGHA = IERC20(0x3129F42a1b574715921cb65FAbB0F0f9bd8b4f39);

    // Timestamp of when the rewards finish
    uint public finishAt;
    // Minimum of last updated time and reward finish time
    uint public updatedAt;
    // Reward to be paid out per second
    uint public rewardRate;
    // Sum of (reward rate * dt * 1e18 / total supply)
    uint public rewardPerTokenStored;
    // User address => rewardPerTokenStored
    mapping(address => uint) public userRewardPerTokenPaid;
    // User address => rewards to be claimed
    mapping(address => uint) public rewards;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event DepositNative(address indexed user, uint256 amount);
    event WithdrawNative(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Redeem(address indexed user, address indexed executor, uint256 amount);
    event GetReward(address indexed user, uint256 amount);

    function deposit(uint256 _amount) external nonReentrant updateReward(msg.sender) {
        accrueInterest();
        require(_amount + totalDeposits <= depositCap, "GHALend: Deposit exceeds cap");
        uint256 xamount = _amount * 1e18/tokenPerxDeposit();
        require(xamount != 0);
        xGND.safeTransferFrom(msg.sender, address(this), _amount);
        xdeposits[msg.sender] += xamount;
        totalDeposits += _amount;
        totalxDeposits += xamount;
        updateAPR();
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external nonReentrant updateReward(msg.sender) {
        accrueInterest();
        uint256 deposits = xdeposits[msg.sender] * tokenPerxDeposit()/1e18;
        uint256 xamount;
        if (_amount > deposits) {
            // withdraw all
            xamount = xdeposits[msg.sender];
            xdeposits[msg.sender] -= xamount;
            totalDeposits -= deposits;
            xGND.safeTransfer(msg.sender, deposits);
            emit Withdraw(msg.sender, deposits);
        } else {
            xamount = _amount * 1e18/tokenPerxDeposit() + 1;
            xdeposits[msg.sender] -= xamount;
            totalDeposits -=_amount;
            xGND.safeTransfer(msg.sender, _amount);
            emit Withdraw(msg.sender, _amount);
        }
        totalxDeposits -= xamount;
        updateAPR();
    }

    function depositNative(uint256 _amount) external nonReentrant {
        require(_amount + totalNativeDeposits <= nativeDepositCap, "GHALend: Deposit exceeds cap");
        GND.safeTransferFrom(msg.sender, address(this), _amount);
        nativeDeposits[msg.sender] += _amount;
        totalNativeDeposits += _amount;
        emit DepositNative(msg.sender, _amount);
    }
    function withdrawNative(uint256 _amount) external nonReentrant {
        accrueInterest();
        uint256 freeCollateral;
        if (LTV == 0) {
            require(xborrows[msg.sender] == 0, "GHALend: Insufficient collateral");
            freeCollateral = valueOfDeposits(msg.sender);
        } else {
            freeCollateral = valueOfDeposits(msg.sender)
                - xborrows[msg.sender] * tokenPerxBorrow()/1e18 * MAX_BPS/LTV;
        }
        require(freeCollateral >= _amount, "GHALend: Insufficient collateral");
        nativeDeposits[msg.sender] -= _amount;
        totalNativeDeposits -= _amount;
        GND.safeTransfer(msg.sender, _amount);
        updateAPR();
        emit WithdrawNative(msg.sender, _amount);
    }

    function borrow(uint256 _amount) external nonReentrant {
        accrueInterest();
        require(_amount + totalBorrows <= borrowCap, "GHALend: Borrow exceeds cap");
        uint256 totalBorrowable = valueOfDeposits(msg.sender) * LTV/MAX_BPS;
        uint256 tokenPerxB = tokenPerxBorrow();
        uint256 borrowable = totalBorrowable - xborrows[msg.sender] * tokenPerxB/1e18;
        require(_amount < borrowable, "GHALend: Insufficient collateral");
        uint256 xamount = _amount * 1e18/tokenPerxB;
        require(xamount != 0);
        xborrows[msg.sender] += xamount;
        totalBorrows += _amount;
        totalxBorrows += xamount;
        xGND.safeTransfer(msg.sender, _amount);
        updateAPR();
        emit Borrow(msg.sender, _amount);
    }

    function repay(uint256 _amount) external nonReentrant {
        accrueInterest();
        uint256 borrows = xborrows[msg.sender] * tokenPerxBorrow()/1e18 + 1;
        uint256 xamount;
        if (_amount > borrows) {
            // repay all
            xamount = xborrows[msg.sender];
            xGND.safeTransferFrom(msg.sender, address(this), borrows + 1);
            totalBorrows -= borrows;
            emit Repay(msg.sender, borrows);
        } else {
            xamount = _amount * 1e18/tokenPerxBorrow();
            xGND.safeTransferFrom(msg.sender, address(this), _amount);
            totalBorrows -= _amount;
            emit Repay(msg.sender, _amount);
        }
        xborrows[msg.sender] -= xamount;
        totalxBorrows -= xamount;
        updateAPR();
    }

    function tokenPerxDeposit() internal view returns (uint256) {
        if (totalxDeposits == 0) {
            return 1e18;
        }
        return totalDeposits * 1e18 / totalxDeposits;
    }

    function tokenPerxBorrow() internal view returns (uint256) {
        if (totalxBorrows == 0) {
            return 1e18;
        }
        return totalBorrows * 1e18 / totalxBorrows;
    }

    function borrowAPR() public view returns (uint256) {
        if (totalDeposits == 0 || totalBorrows == 0) {
            return 0;
        }
        uint256 utilizationRatio = totalBorrows*1e18/totalDeposits;
        uint256 APR;

        if (utilizationRatio < kink) {
            APR = (slope1 * utilizationRatio*100) / 1e18 + base;
        } else {
            uint256 excessUtilization = utilizationRatio - kink;
            APR = (slope1 * kink*100) / 1e18 + (slope2 * excessUtilization*100) / 1e18 + base;
        }

        return APR;
    }

    // adds accrued interest
    function accrueInterest() internal {
        uint256 reward = pendingInterest();
        lastUpdate = block.timestamp;
        uint256 fees = reward * feeRate / MAX_BPS;
        totalDeposits += (reward - fees);
        totalBorrows += reward;
        // treasury deposits fees back into protocol
        uint256 tokenPerxD = tokenPerxDeposit();
        xdeposits[treasury] += fees * 1e18/tokenPerxD;
        totalxDeposits += fees * 1e18/tokenPerxD;
        totalDeposits += fees;
    }
    function pendingInterest() internal view returns (uint256) {
        uint256 timepass = block.timestamp - lastUpdate;
        return earnRateSec*timepass;
    }

    // updates APR
    function updateAPR() internal {
        // function is always called after accrueInterest() so totalBorrows refers to the true value
        earnRateSec = totalBorrows*borrowAPR()/1e18/(365 days);
    }

    // returns value of a user's collateral in token
    function valueOfDeposits(address _user) internal view returns (uint256) {
        return nativeDeposits[_user];
    }

    // 1e18 means 100% LTV
    function userLTV(address _user) public view returns (uint256) {
        if(valueOfDeposits(_user) == 0) {
            return type(uint256).max;
        }
        return xborrows[_user] * tokenPerxBorrow() / valueOfDeposits(_user);
    }

    // liquidate xGND -> GND at dutch auction
    function redeem(address _user, uint256 _amount) external nonReentrant {
        require(_amount != 0);
        require(_user != msg.sender, "GHALend: can't redeem yourself");
        accrueInterest();
        uint256 nativeAmount = _amount * liquidationPrice(_user)/1e18;
        uint256 tokenPerxB = tokenPerxBorrow();
        xborrows[_user] -= _amount * 1e18/tokenPerxB;
        nativeDeposits[_user] -= nativeAmount;
        totalBorrows -= _amount;
        totalxBorrows -= _amount * 1e18/tokenPerxB;
        totalNativeDeposits -= nativeAmount;
        xGND.safeTransferFrom(msg.sender, address(this), _amount);
        GND.safeTransfer(msg.sender, nativeAmount);
        require(userLTV(_user) > redLTV * 1e18/MAX_BPS, "GHALend: too much redemption");
        updateAPR();
        emit Redeem(_user, msg.sender, _amount);
    }

    // price is a linear function from 0 to 1e18 from redLTV to 100%
    // returns amount of GND received per xGND
    function liquidationPrice(address _user) internal view returns(uint256) {
        //            = max  * (fraction)
        uint256 price = 1e18 * (userLTV(_user) * MAX_BPS/1e18 - redLTV)/(MAX_BPS - redLTV);
        return _min(1e18, price);
    }

    function setCaps(uint256 _depositCap, uint256 _nativeDepositCap, uint256 _borrowCap) external onlyOwner {
        depositCap = _depositCap;
        nativeDepositCap = _nativeDepositCap;
        borrowCap = _borrowCap;
    }

    function updateLTVs(uint256 _LTV, uint256 _redLTV) external onlyOwner {
        require(_LTV <= MAX_BPS, "out of range");
        require(redLTV <= MAX_BPS, "out of range");
        require(redLTV > _LTV, "too low");
        LTV = _LTV;
        redLTV = _redLTV;
    }

    function updateInterestRateCurve(uint256 _base, uint256 _slope1, uint256 _kink, uint256 _slope2) external onlyOwner {
        base = _base;
        slope1 = _slope1;
        kink = _kink;
        slope2 = _slope2;
    }

    function changeFees(uint256 _feeRate, address _treasury) external onlyOwner {
        accrueInterest();
        require(_feeRate <= MAX_BPS, "out of range");
        require(_treasury != address(0));
        feeRate = _feeRate;
        treasury = _treasury;
        updateAPR();
    }

    // in a rare shortfall event, we may need to yoink back deposits
    // ownership is guarded by a 2/3 multisig of internally doxxed members
    function yoink(IERC20 _token, address _to, uint256 _amount) external onlyOwner {
        _token.safeTransfer(_to, _amount);
    }

    // modified synthetix staking:

    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        updatedAt = lastTimeRewardApplicable();

        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }

        _;
    }

    function lastTimeRewardApplicable() internal view returns (uint) {
        return _min(finishAt, block.timestamp);
    }

    function rewardPerToken() public view returns (uint) {
        if (totalxDeposits == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            (rewardRate * (lastTimeRewardApplicable() - updatedAt) * 1e18) /
            totalxDeposits;
    }

    function earned(address _account) public view returns (uint) {
        return
            ((xdeposits[_account] *
                (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e18) +
            rewards[_account];
    }

    function getReward() external updateReward(msg.sender) {
        uint reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        esGHA.safeTransfer(msg.sender, reward * esRatio / MAX_BPS);
        GHA.safeTransfer(msg.sender, reward * (MAX_BPS - esRatio) / MAX_BPS);
        emit GetReward(msg.sender, reward);
    }

    function setRewards(uint256 _rewardRate, uint256 _finishAt, uint256 _esRatio) external onlyOwner updateReward(address(0)) {
        require(_esRatio <= MAX_BPS, "out of range");
        esRatio = _esRatio;
        rewardRate = _rewardRate;
        finishAt = _finishAt;
        uint256 duration = finishAt - block.timestamp;
        require(
            rewardRate * duration * esRatio / MAX_BPS <= esGHA.balanceOf(address(this)),
            "es reward amount > balance"
        );
        require(
            rewardRate * duration * (MAX_BPS - esRatio) / MAX_BPS <= GHA.balanceOf(address(this)),
            "reward amount > balance"
        );
        updatedAt = block.timestamp;
    }

    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }

    // ui helpers
    function pendingTokenPerxDeposit() external view returns (uint256) {
        if (totalxDeposits == 0) {
            return 1e18;
        }
        return (totalDeposits + pendingInterest() * (MAX_BPS - feeRate) / MAX_BPS) * 1e18 / totalxDeposits;
    }

    function pendingTokenPerxBorrow() external view returns (uint256) {
        if (totalxBorrows == 0) {
            return 1e18;
        }
        return (totalBorrows + pendingInterest()) * 1e18 / totalxBorrows;
    }

    function depositAPR() external view returns (uint256) {
        return borrowAPR() * totalBorrows / totalDeposits * (MAX_BPS - feeRate) / MAX_BPS;
    }
}
