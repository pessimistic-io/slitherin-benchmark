// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.18;

import "./SafeMath.sol";
import "./Math.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

contract TCHSale is Ownable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant TWENTY = 20;
    uint256 private constant HUNDRED = 100;
    uint256 private constant MIN_MONTH_FOR_FULL_REWARD = 6;

    uint256 private constant ONE_MONTH_IN_SEC = 2592000;
    uint256 private constant MAX_DIFF_NEXT_DEADLINE = ONE_MONTH_IN_SEC;
    uint256 private constant BASE = 10 ** 18;

    uint256 private constant SOFT_CAP = 1 * BASE;
    uint256 private constant HARD_CAP = 3 * BASE;
    uint256 private constant TCH_PRICE = 5 * (10 ** 15);

    IERC20 private immutable _rewardToken;

    bool private _withdrawContractBalance;
    bool private _isSaleStart;
    uint256 private _saleDeadline;
    uint256 private _totalDepositBalance;

    mapping(address => uint256) private _userDeposit;
    mapping(address => uint256) private _userClaimedRewards;
    mapping(address => bool) private _isGetMoneyBackOrReward;

    event SaleStarted(uint256 _blockTimestamp);
    event DeadlineChanged(uint256 _newSaleDeadline);
    event IncreaseTotalReward(uint256 _totalRewardToken);
    event WithdrawTotalReward(uint256 _totalRewardToken);
    event Deposit(address indexed _account, uint256 _deposit, uint256 _totalUserDeposit, uint256 _totalContracDeposit);
    event Withdraw(address indexed _account, uint256 _userDeposit, uint256 _userTCH);

    constructor(address rewardToken) {
        _requireNonZeroAddress(rewardToken);
        _rewardToken = IERC20(rewardToken);
    }

    function setIsSaleStart() external onlyOwner {
        require(!_isSaleStart, "Already started");

        _isSaleStart = true;
        emit SaleStarted(_getBlockTimestamp());
    }

    function getIsSaleStart() external view returns (bool) {
        return _isSaleStart;
    }

    function setSaleDeadline(uint256 saleDeadline) external onlyOwner {
        require(_saleDeadline < saleDeadline, "Not correct");
        require(_saleDeadline > 0 || saleDeadline > _getBlockTimestamp(), "Time has passed");
        require(_saleDeadline == 0 || _saleDeadline > _getBlockTimestamp(), "Time is over");
        require(_saleDeadline == 0 || _saleDeadline + MAX_DIFF_NEXT_DEADLINE > saleDeadline, "Big value");

        _saleDeadline = saleDeadline;

        emit DeadlineChanged(saleDeadline);
    }

    function getSaleDeadline() external view returns (uint256) {
        return _saleDeadline;
    }

    function withdrawRewardTokens() external onlyOwner {
        require(!_isSaleStart || _saleDeadline < _getBlockTimestamp(), "Not allowed");

        uint256 _totalRewardToken = _getTotalRewardToken();
        require(_totalRewardToken > 0, "Empty balance");

        if (_totalDepositBalance >= SOFT_CAP) {
            uint minDeposit = _totalDepositBalance.min(HARD_CAP);
            uint256 tokensForCurrentDeposit = (minDeposit * BASE) / TCH_PRICE;
            require(_totalRewardToken > tokensForCurrentDeposit, "Not enough");

            _rewardToken.safeTransfer(_msgSender(), _totalRewardToken - tokensForCurrentDeposit);

            emit WithdrawTotalReward(tokensForCurrentDeposit);
        } else {
            _rewardToken.safeTransfer(_msgSender(), _totalRewardToken);

            emit WithdrawTotalReward(_totalRewardToken);
        }
    }

    function increaseTotalRewardToken(uint256 amount) external onlyOwner {
        uint256 ownerBalance = _rewardToken.balanceOf(address(_msgSender()));
        require(ownerBalance > amount, "Not enough");
        require(amount > 0, "amount = 0");

        uint256 _totalRewardToken = _getTotalRewardToken();
        require(_totalRewardToken > 0 || amount == ((HARD_CAP * BASE) / TCH_PRICE), "Not correct");

        _rewardToken.safeTransferFrom(address(_msgSender()), address(this), amount);
        _totalRewardToken = _totalRewardToken + amount;

        emit IncreaseTotalReward(_totalRewardToken);
    }

    function getTotalDepositBalance() external view returns (uint256) {
        return _totalDepositBalance;
    }

    function getUserDeposit(address account) external view returns (uint256) {
        return _userDeposit[account];
    }

    function getUserClaimedRewards(address account) external view returns (uint256) {
        return _userClaimedRewards[account];
    }

    receive() external payable {
        deposit();
    }

    function withdrawContractBalance() external onlyOwner {
        require(!_withdrawContractBalance, "Already processed");
        _requireDeadLineIsOver();
        require(SOFT_CAP <= _totalDepositBalance, "lt SOFT_CAP");

        payable(_msgSender()).transfer(_totalDepositBalance.min(HARD_CAP));
        _withdrawContractBalance = true;
    }

    function deposit() payable public {
        _requireSaleStarts();
        require(_saleDeadline > _getBlockTimestamp(), "Time is over");

        _userDeposit[_msgSender()] = _userDeposit[_msgSender()] + msg.value;
        _totalDepositBalance = _totalDepositBalance + msg.value;

        emit Deposit(_msgSender(), msg.value, _userDeposit[_msgSender()], _totalDepositBalance);
    }

    function withdraw() external {
        _requireSaleStarts();
        require(_totalDepositBalance < SOFT_CAP, "gte SOFT_CAP");
        _requireDeadLineIsOver();

        _requireNonEmptyDeposit(_msgSender());

        _requireFirstMoneyBackOrReward(_msgSender());
        _isGetMoneyBackOrReward[_msgSender()] = true;

        payable(_msgSender()).transfer(_userDeposit[_msgSender()]);

        emit Withdraw(_msgSender(), _userDeposit[_msgSender()], 0);
    }

    function claimTCH() external {
        _requireSaleStarts();
        _requireDeadLineIsOver();
        require(SOFT_CAP <= _totalDepositBalance, "lt SOFT_CAP");
        require(_totalDepositBalance < HARD_CAP, "gte HARD_CAP");
        _requireNonEmptyDeposit(_msgSender());

        uint256 reward = calculateCurrentReward(_msgSender());
        require(reward > 0, "reward = 0");
        _requireEnoughTCHBalance(reward);

        _requireFirstMoneyBackOrReward(_msgSender());
        _isGetMoneyBackOrReward[_msgSender()] = true;
        _userClaimedRewards[_msgSender()] = _userClaimedRewards[_msgSender()] + reward;

        _rewardToken.safeTransfer(_msgSender(), reward);

        emit Withdraw(_msgSender(), 0, reward);
    }

    function claimTCHAndDeposit() external {
        _requireSaleStarts();
        _requireDeadLineIsOver();
        require(HARD_CAP <= _totalDepositBalance, "lt HARD_CAP");

        _requireNonEmptyDeposit(_msgSender());

        uint256 reward = calculateCurrentReward(_msgSender());
        _requireEnoughTCHBalance(reward);

        _requireFirstMoneyBackOrReward(_msgSender());
        _isGetMoneyBackOrReward[_msgSender()] = true;
        _userClaimedRewards[_msgSender()] = _userClaimedRewards[_msgSender()] + reward;

        if (reward > 0) {
            _rewardToken.safeTransfer(_msgSender(), reward);
        }

        uint256 rewardInETH = (calculateFullReward(_msgSender()) * TCH_PRICE) / BASE;
        uint256 wad = 0;
        if (rewardInETH < _userDeposit[_msgSender()]) {
            wad = _userDeposit[_msgSender()] - rewardInETH;
            payable(_msgSender()).transfer(wad);
        }

        emit Withdraw(_msgSender(), wad, reward);
    }

    function claimRemainingRewards() external {
        _requireSaleStarts();
        _requireDeadLineIsOver();
        require(_isGetMoneyBackOrReward[_msgSender()], "Not processed");
        uint256 reward = calculateCurrentReward(_msgSender());
        require(reward > 0, "reward = 0");

        _userClaimedRewards[_msgSender()] = _userClaimedRewards[_msgSender()] + reward;
        _rewardToken.safeTransfer(_msgSender(), reward);

        emit Withdraw(_msgSender(), 0, reward);
    }

    function calculateCurrentReward(address account) public view returns(uint256) {
        _requireSaleStarts();
        _requireDeadLineIsOver();

        if (_userDeposit[account] == 0 || _totalDepositBalance < SOFT_CAP) {
            return 0;
        }

        uint256 fullReward = calculateFullReward(account);

        if (_userClaimedRewards[account] >= fullReward) {
            return 0;
        }

        uint256 twentyRewardPercent = (fullReward * TWENTY) / HUNDRED;
        uint256 eightyPercentReward = fullReward - twentyRewardPercent;
        uint256 multiplier = MIN_MONTH_FOR_FULL_REWARD.min((_getBlockTimestamp() - _saleDeadline) / ONE_MONTH_IN_SEC);

        return twentyRewardPercent + ((eightyPercentReward * multiplier) / MIN_MONTH_FOR_FULL_REWARD) - _userClaimedRewards[account];
    }

    function calculateFullReward(address account) public view returns(uint256) {
        if (_userDeposit[account] == 0 || _totalDepositBalance < SOFT_CAP) {
            return 0;
        }

        if (HARD_CAP <= _totalDepositBalance) {
            return ((_userDeposit[account] * HARD_CAP * BASE) / _totalDepositBalance) / TCH_PRICE;
        }

        return (_userDeposit[account] * BASE) / TCH_PRICE;
    }

    function _getBlockTimestamp() internal view returns(uint256) {
        return block.timestamp;
    }

    function _getTotalRewardToken() internal view returns (uint256) {
        return _rewardToken.balanceOf(address(this));
    }

    function _requireDeadLineIsOver() internal view virtual {
        require(_saleDeadline < _getBlockTimestamp(), "Sale not completed");
    }

    function _requireFirstMoneyBackOrReward(address account) internal view virtual {
        require(!_isGetMoneyBackOrReward[account], "Already processed");
    }

    function _requireNonEmptyDeposit(address account) internal view virtual {
        require(_userDeposit[account] > 0, "No deposit");
    }

    function _requireSaleStarts() internal view virtual {
        require(_isSaleStart, "Sale not started");
        require(_saleDeadline > 0, "_saleDeadline=0");
        require(_getTotalRewardToken() > 0, "_totalRewardToken=0");
    }

    function _requireEnoughTCHBalance(uint256 reward) internal view virtual {
        uint256 contractBalance = _rewardToken.balanceOf(address(this));
        require(contractBalance >= reward, "Not enough TCH");
    }

    function _requireNonZeroAddress(address account) internal view virtual {
        require(account != address(0), "Zero address");
    }
}

