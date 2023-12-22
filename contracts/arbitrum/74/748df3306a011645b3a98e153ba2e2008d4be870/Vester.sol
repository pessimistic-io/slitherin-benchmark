// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./OwnableUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IVester.sol";
import "./IRewardTracker.sol";
import "./ImplementationGuard.sol";

contract Vester is ReentrancyGuardUpgradeable, OwnableUpgradeable, IVester, ImplementationGuard {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    string public name;
    string public symbol;
    uint8 public decimals = 18;

    uint256 public vestingDuration;

    address public esToken;
    address public pairToken;
    address public claimableToken;

    address public rewardTracker; // staked GMX

    uint256 public override totalSupply;
    uint256 public pairSupply;

    bool public hasMaxVestableAmount;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public override pairAmounts;
    mapping(address => uint256) public override cumulativeClaimAmounts;
    mapping(address => uint256) public override claimedAmounts;
    mapping(address => uint256) public lastVestingTimes;

    mapping(address => bool) public isHandler;

    bool public hasVolumeLimit;
    mapping(address => uint256) public historicalCumulativeClaimAmounts;

    address[] public rewardTrackers;

    event Claim(address receiver, uint256 amount);
    event Deposit(address account, uint256 amount);
    event Withdraw(address account, uint256 claimedAmount, uint256 balance);
    event PairTransfer(address indexed from, address indexed to, uint256 value);

    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _vestingDuration,
        address _esToken,
        address _pairToken,
        address _claimableToken,
        address _rewardTracker,
        bool _hasVolumeLimit
    ) external initializer onlyDelegateCall {
        __Ownable_init();

        name = _name;
        symbol = _symbol;

        vestingDuration = _vestingDuration;

        esToken = _esToken;
        pairToken = _pairToken;
        claimableToken = _claimableToken;

        rewardTracker = _rewardTracker;

        if (rewardTracker != address(0)) {
            hasMaxVestableAmount = true;
        }

        hasVolumeLimit = _hasVolumeLimit;
    }

    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }

    function setHasMaxVestableAmount(bool _hasMaxVestableAmount) external onlyOwner {
        hasMaxVestableAmount = _hasMaxVestableAmount;
    }

    function setRewardTrackers(address[] memory _rewardTrackers) external onlyOwner {
        rewardTrackers = _rewardTrackers;
    }

    function deposit(uint256 _amount) external nonReentrant {
        _deposit(msg.sender, _amount);
    }

    function depositForAccount(address _account, uint256 _amount) external nonReentrant {
        _validateHandler();
        _deposit(_account, _amount);
    }

    function claim() external nonReentrant returns (uint256) {
        return _claim(msg.sender, msg.sender);
    }

    function claimForAccount(address _account, address _receiver) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _claim(_account, _receiver);
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyOwner {
        IERC20Upgradeable(_token).safeTransfer(_account, _amount);
    }

    function withdrawFor(address account, address _receiver) external nonReentrant {
        _validateHandler();
        _withdrawFor(account, _receiver);
    }

    function withdraw() external nonReentrant {
        _withdrawFor(msg.sender, msg.sender);
    }

    function _withdrawFor(address account, address _receiver) internal {
        _claim(account, _receiver);

        uint256 claimedAmount = cumulativeClaimAmounts[account];
        uint256 balance = balances[account];
        uint256 totalVested = balance.add(claimedAmount);
        require(totalVested > 0, "Vester: vested amount is zero");

        if (hasPairToken()) {
            uint256 pairAmount = pairAmounts[account];
            _burnPair(account, pairAmount);
            IERC20Upgradeable(pairToken).safeTransfer(_receiver, pairAmount);
        }

        IERC20Upgradeable(esToken).safeTransfer(_receiver, balance);
        _burn(account, balance);

        delete cumulativeClaimAmounts[account];
        delete claimedAmounts[account];
        delete lastVestingTimes[account];

        emit Withdraw(account, claimedAmount, balance);
    }

    function claimable(address _account) public view override returns (uint256) {
        uint256 amount = cumulativeClaimAmounts[_account].sub(claimedAmounts[_account]);
        uint256 nextClaimable = _getNextClaimableAmount(_account);
        return amount.add(nextClaimable);
    }

    function getMaxVestableAmount(address _account) public view override returns (uint256) {
        if (!hasRewardTracker()) {
            return 0;
        }
        uint256 cumulativeReward;
        if (rewardTrackers.length != 0) {
            for (uint256 i = 0; i < rewardTrackers.length; i++) {
                cumulativeReward += IRewardTracker(rewardTrackers[i]).cumulativeRewards(_account);
            }
        } else {
            cumulativeReward = IRewardTracker(rewardTracker).cumulativeRewards(_account);
        }

        uint256 maxVestableAmount = cumulativeReward;
        uint256 maxAmount = maxVestableAmount;
        if (hasVolumeLimit) {
            return
                maxAmount > historicalCumulativeClaimAmounts[_account]
                    ? maxAmount - historicalCumulativeClaimAmounts[_account]
                    : 0;
        } else {
            return maxAmount;
        }
    }

    function getCombinedAverageStakedAmount(address _account) public view override returns (uint256) {
        uint256 totalCumulativeReward = IRewardTracker(rewardTracker).cumulativeRewards(_account);
        if (totalCumulativeReward == 0) {
            return 0;
        }
        if (rewardTrackers.length != 0) {
            uint256 sum = 0;
            for (uint256 i = 0; i < rewardTrackers.length; i++) {
                sum += IRewardTracker(rewardTrackers[i]).averageStakedAmounts(_account);
            }
            return sum;
        } else {
            return IRewardTracker(rewardTracker).averageStakedAmounts(_account);
        }
    }

    function getPairAmount(address _account, uint256 _esAmount) public view returns (uint256) {
        if (!hasRewardTracker()) {
            return 0;
        }
        uint256 combinedAverageStakedAmount = getCombinedAverageStakedAmount(_account);
        if (combinedAverageStakedAmount == 0) {
            return 0;
        }
        uint256 maxVestableAmount = getMaxVestableAmount(_account);
        if (maxVestableAmount == 0) {
            return 0;
        }
        return _esAmount.mul(combinedAverageStakedAmount).div(maxVestableAmount);
    }

    function hasRewardTracker() public view returns (bool) {
        return rewardTracker != address(0);
    }

    function hasPairToken() public view returns (bool) {
        return pairToken != address(0);
    }

    function getTotalVested(address _account) public view returns (uint256) {
        return balances[_account].add(cumulativeClaimAmounts[_account]);
    }

    function balanceOf(address _account) public view override returns (uint256) {
        return balances[_account];
    }

    // empty implementation, tokens are non-transferrable
    function transfer(address /* recipient */, uint256 /* amount */) public pure override returns (bool) {
        revert("Vester: non-transferrable");
    }

    // empty implementation, tokens are non-transferrable
    function allowance(address /* owner */, address /* spender */) public view virtual override returns (uint256) {
        return 0;
    }

    // empty implementation, tokens are non-transferrable
    function approve(address /* spender */, uint256 /* amount */) public virtual override returns (bool) {
        revert("Vester: non-transferrable");
    }

    // empty implementation, tokens are non-transferrable
    function transferFrom(
        address /* sender */,
        address /* recipient */,
        uint256 /* amount */
    ) public virtual override returns (bool) {
        revert("Vester: non-transferrable");
    }

    function getVestedAmount(address _account) public view override returns (uint256) {
        uint256 balance = balances[_account];
        uint256 cumulativeClaimAmount = cumulativeClaimAmounts[_account];
        return balance.add(cumulativeClaimAmount);
    }

    function _mint(address _account, uint256 _amount) private {
        require(_account != address(0), "Vester: mint to the zero address");

        totalSupply = totalSupply.add(_amount);
        balances[_account] = balances[_account].add(_amount);

        emit Transfer(address(0), _account, _amount);
    }

    function _mintPair(address _account, uint256 _amount) private {
        require(_account != address(0), "Vester: mint to the zero address");

        pairSupply = pairSupply.add(_amount);
        pairAmounts[_account] = pairAmounts[_account].add(_amount);

        emit PairTransfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) private {
        require(_account != address(0), "Vester: burn from the zero address");

        balances[_account] = balances[_account].sub(_amount, "Vester: burn amount exceeds balance");
        totalSupply = totalSupply.sub(_amount);

        emit Transfer(_account, address(0), _amount);
    }

    function _burnPair(address _account, uint256 _amount) private {
        require(_account != address(0), "Vester: burn from the zero address");

        pairAmounts[_account] = pairAmounts[_account].sub(_amount, "Vester: burn amount exceeds balance");
        pairSupply = pairSupply.sub(_amount);

        emit PairTransfer(_account, address(0), _amount);
    }

    function _deposit(address _account, uint256 _amount) private {
        require(_amount > 0, "Vester: invalid _amount");

        _updateVesting(_account);

        IERC20Upgradeable(esToken).safeTransferFrom(_account, address(this), _amount);

        _mint(_account, _amount);

        if (hasPairToken()) {
            uint256 pairAmount = pairAmounts[_account];
            uint256 nextPairAmount = getPairAmount(_account, balances[_account]);
            if (nextPairAmount > pairAmount) {
                uint256 pairAmountDiff = nextPairAmount.sub(pairAmount);
                IERC20Upgradeable(pairToken).safeTransferFrom(_account, address(this), pairAmountDiff);
                _mintPair(_account, pairAmountDiff);
            }
        }

        if (hasMaxVestableAmount) {
            uint256 maxAmount = getMaxVestableAmount(_account);
            if (hasVolumeLimit) {
                require(balanceOf(_account) <= maxAmount, "Vester: max vestable amount exceeded");
            } else {
                require(getTotalVested(_account) <= maxAmount, "Vester: max vestable amount exceeded");
            }
        }

        emit Deposit(_account, _amount);
    }

    function _updateVesting(address _account) private {
        uint256 amount = _getNextClaimableAmount(_account);
        lastVestingTimes[_account] = _blockTime();

        if (amount == 0) {
            return;
        }

        // transfer claimableAmount from balances to cumulativeClaimAmounts
        _burn(_account, amount);
        cumulativeClaimAmounts[_account] = cumulativeClaimAmounts[_account].add(amount);
        historicalCumulativeClaimAmounts[_account] = historicalCumulativeClaimAmounts[_account].add(amount);

        // IMintable(esToken).burn(address(this), amount);
    }

    function _getNextClaimableAmount(address _account) private view returns (uint256) {
        uint256 timeDiff = _blockTime().sub(lastVestingTimes[_account]);

        uint256 balance = balances[_account];
        if (balance == 0) {
            return 0;
        }

        uint256 vestedAmount = getVestedAmount(_account);
        uint256 claimableAmount = vestedAmount.mul(timeDiff).div(vestingDuration);

        if (claimableAmount < balance) {
            return claimableAmount;
        }

        return balance;
    }

    function _claim(address _account, address _receiver) private returns (uint256) {
        _updateVesting(_account);
        uint256 amount = claimable(_account);
        claimedAmounts[_account] = claimedAmounts[_account].add(amount);
        IERC20Upgradeable(claimableToken).safeTransfer(_receiver, amount);
        emit Claim(_account, amount);
        return amount;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "Vester: forbidden");
    }

    function _blockTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}

