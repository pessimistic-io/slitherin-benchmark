// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { ERC20BurnableUpgradeable } from "./ERC20BurnableUpgradeable.sol";

import { PausableUpgradeable } from "./PausableUpgradeable.sol";

contract Vester1 is IERC20Upgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    string public name;
    string public symbol;
    uint8 public decimals;

    uint256 public VESTING_DURATION;
    uint256 private vesting_duration;

    address public esToken;
    address public claimableToken;

    uint256 public totalSupply;
    address public vester3Months;
    uint256 private burnRate;
    uint256 private burnRateDenominator; // 10000 = 100%
    uint256 private MAX_PRECISION;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public cumulativeClaimAmounts;
    mapping(address => uint256) public claimedAmounts;
    mapping(address => uint256) public lastVestingTimes;
    mapping(address => uint256) public vestingEndTimes; //timestamp of the end of vesting

    mapping(address => bool) public isHandler;

    event Claim(address indexed receiver, uint256 amount);
    event Deposit(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 claimedAmount, uint256 balance);
    event HandlerSet(address handler, bool isActive);
    event SetVester3Months(address indexed vester3Months);

    ///@custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _esToken,
        address _claimableToken
    ) external initializer {
        //Implement zero address checks
        require(_esToken != address(0), "Vaultka: Invalid address");
        require(_claimableToken != address(0), "Vaultka: Invalid address");
        name = _name;
        symbol = _symbol;
        burnRate = 1000;
        burnRateDenominator = 10000;
        decimals = 18;
        VESTING_DURATION = 180 days;
        MAX_PRECISION = 1e18;
        esToken = _esToken;
        claimableToken = _claimableToken;
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        setHandler(msg.sender, true);
    }

    function setVester3Months(address _vester3Months) external onlyOwner {
        //Implement zero address checks
        require(_vester3Months != address(0), "Vaultka: Invalid address");
        vester3Months = _vester3Months;
        emit SetVester3Months(_vester3Months);
    }

    function deposit(uint256 _amount) external nonReentrant {
        _validateHandler();
        _deposit(msg.sender, _amount);
    }

    function depositForAccount(address _account, uint256 _amount) external nonReentrant {
        //Implement zero address checks
        require(_account != address(0), "Vaultka: Invalid address");
        _validateHandler();
        _deposit(_account, _amount);
    }

    function claim() external nonReentrant returns (uint256) {
        return _claim(msg.sender, msg.sender);
    }

    function recoverToken(address _token, address _account, uint256 _amount) external onlyOwner {
        require(_token != address(this) && _token != esToken, "Vester: cannot withdraw this token");

        IERC20Upgradeable(_token).safeTransfer(_account, _amount);
    }

    function withdraw() external nonReentrant {
        address account = msg.sender;
        address _receiver = account;
        _claim(account, _receiver);

        uint256 claimedAmount = cumulativeClaimAmounts[account];
        uint256 balance = balances[account];
        uint256 totalVested = balance + claimedAmount;
        require(totalVested > 0, "Vester: vested amount is zero");

        IERC20Upgradeable(esToken).safeTransfer(_receiver, balance);
        _burn(account, balance);

        delete cumulativeClaimAmounts[account];
        delete claimedAmounts[account];
        delete lastVestingTimes[account];
        delete vestingEndTimes[account];

        emit Withdraw(account, claimedAmount, balance);
    }

    // empty implementation, tokens are non-transferrable
    function approve(address /* spender */, uint256 /* amount */) external virtual returns (bool) {
        revert("Vester: non-transferrable");
    }

    function getTotalVested(address _account) public view returns (uint256) {
        return balances[_account] + cumulativeClaimAmounts[_account];
    }

    function balanceOf(address _account) public view returns (uint256) {
        return balances[_account];
    }

    // empty implementation, tokens are non-transferrable
    function allowance(address /* owner */, address /* spender */) external view virtual returns (uint256) {
        return 0;
    }

    // empty implementation, tokens are non-transferrable
    function transfer(address /* recipient */, uint256 /* amount */) external pure returns (bool) {
        revert("Vester: non-transferrable");
    }

    // empty implementation, tokens are non-transferrable
    function transferFrom(
        address /* sender */,
        address /* recipient */,
        uint256 /* amount */
    ) external virtual returns (bool) {
        revert("Vester: non-transferrable");
    }

    function setHandler(address _handler, bool _isActive) public onlyOwner {
        //Implement zero address checks
        require(_handler != address(0), "Vaultka: Invalid address");
        isHandler[_handler] = _isActive;
        emit HandlerSet(_handler, _isActive);
    }

    function setHandlers(address[] memory _handlers, bool _isActive) external onlyOwner {
        for (uint256 i = 0; i < _handlers.length; i++) {
            setHandler(_handlers[i], _isActive);
        }
    }

    function claimable(address _account) public view returns (uint256) {
        // Implement zero address checks
        require(_account != address(0), "Vaultka: Invalid address");
        uint256 amount = cumulativeClaimAmounts[_account] - claimedAmounts[_account];
        uint256 nextClaimable = _getNextClaimableAmount(_account);
        return amount + nextClaimable;
    }

    function remainingVestingAmount(address _account) public view returns (uint256) {
        uint256 balance = balances[_account];
        uint256 multiplier = (burnRateDenominator * MAX_PRECISION) / (burnRateDenominator - burnRate);
        return balance - ((claimable(_account) * multiplier) / MAX_PRECISION);
    }

    function remainingTimeForVesting(address _account) external view returns (uint256) {
        require(_account != address(0), "Vester: Invalid address");
        if (vestingEndTimes[_account] < block.timestamp) {
            return 0;
        }

        uint256 timeDiff = vestingEndTimes[_account] - block.timestamp;

        return timeDiff;
    }

    function _mint(address _account, uint256 _amount) private {
        // require(_account != address(0), "Vester: mint to the zero address");

        totalSupply += _amount;

        balances[_account] += _amount;

        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) private {
        // require(_account != address(0), "Vester: burn from the zero address");

        balances[_account] -= _amount;
        totalSupply -= _amount;

        emit Transfer(_account, address(0), _amount);
    }

    function _deposit(address _account, uint256 _amount) private {
        require(_amount > 0, "Vester: invalid _amount");

        _claim(_account, _account);

        vestingEndTimes[_account] = block.timestamp + 2592000;

        IERC20Upgradeable(esToken).safeTransferFrom(_account, address(this), _amount);

        _mint(_account, _amount);

        emit Deposit(_account, _amount);
    }

    function _updateVesting(address _account) private {
        //amount to be claimed;
        uint256 amount = _getNextClaimableAmount(_account);

        lastVestingTimes[_account] = block.timestamp;

        if (amount == 0) {
            return;
        }
        //burning amount:
        uint256 multiplier = (burnRateDenominator * MAX_PRECISION) / (burnRateDenominator - burnRate);
        _burn(_account, (amount * multiplier) / MAX_PRECISION);
        cumulativeClaimAmounts[_account] = cumulativeClaimAmounts[_account] + amount;
        //

        ERC20BurnableUpgradeable(esToken).burn((amount * multiplier) / MAX_PRECISION);
        ERC20BurnableUpgradeable(claimableToken).burn(((amount * multiplier) / MAX_PRECISION) - amount);
    }

    function _getNextClaimableAmount(address _account) private view returns (uint256) {
        uint256 balance = balances[_account];
        if (balance == 0) {
            return 0;
        }

        uint256 timeDiff = block.timestamp - lastVestingTimes[_account];

        if (timeDiff > vesting_duration) {
            timeDiff = vesting_duration;
        }

        uint256 multiplier = (burnRateDenominator * MAX_PRECISION) / (burnRateDenominator - burnRate);

        uint256 vestedAmount = getTotalVested(_account);
        uint256 claimableAmount = ((vestedAmount * timeDiff) * MAX_PRECISION) / vesting_duration / multiplier;

        uint256 maxClaimbleAmount = (balance * MAX_PRECISION) / multiplier;

        if (claimableAmount < maxClaimbleAmount) {
            return claimableAmount;
        }

        return maxClaimbleAmount;
    }

    function _claim(address _account, address _receiver) private returns (uint256) {
        _updateVesting(_account);
        uint256 amount = claimable(_account);
        claimedAmounts[_account] += amount;
        IERC20Upgradeable(claimableToken).safeTransfer(_receiver, amount);
        emit Claim(_account, amount);
        return amount;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "Vester: forbidden");
    }

    function transferVKAtoVester3Months(uint256 _amount) external onlyOwner {
        require(vester3Months != address(0), "Vester: Invalid address");
        //require amount is not 0

        IERC20Upgradeable(claimableToken).safeTransfer(vester3Months, _amount);
    }
}

