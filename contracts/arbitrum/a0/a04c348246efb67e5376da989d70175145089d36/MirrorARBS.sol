// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./Pausable.sol";
import "./IArbswapToken.sol";

contract MirrorARBS is Ownable, Pausable, ERC20 {
    using SafeERC20 for IArbswapToken;
    using SafeERC20 for IERC20;

    IArbswapToken public immutable token; // Arbswap token

    mapping(address => uint256) public userLastDepositedTime; // keeps track of deposited time

    address public admin;
    address public treasury;
    address public devAddr;

    uint256 public constant MAX_WITHDRAW_FEE = 1000; // 10%
    uint256 public constant MAX_WITHDRAW_FEE_PERIOD = 30 days; // 30 days
    uint256 public constant MaxArbsPerSecond = 10 ether; // Max arbs per second.
    uint256 public constant MIN_DEPOSIT_AMOUNT = 0.00001 ether;

    uint256 public withdrawFee = 100; // 1%
    uint256 public withdrawFeePeriod = 3 days; // 3 days
    uint256 public arbsPerSecond = 1 ether; // arbs tokens created 1 per second.
    uint256 public latestMintTime;
    bool public Mintable = true;

    event Deposit(address indexed sender, uint256 amount, uint256 shares, uint256 lastDepositedTime);
    event Withdraw(address indexed sender, uint256 amount, uint256 shares, uint256 withdrawFee);
    event SetMintable(bool mintable, uint256 time);

    /**
     * @notice Constructor
     * @param _token: Arbswap token contract
     * @param _admin: address of the admin
     * @param _treasury: address of the treasury (collects fees)
     * @param _devAddr: address of the dev
     * @param _startMintTime: start of mint time
     */
    constructor(
        IArbswapToken _token,
        address _admin,
        address _treasury,
        address _devAddr,
        uint256 _startMintTime
    ) ERC20("Mirror ARBS", "xARBS") {
        require(_startMintTime > block.timestamp);
        token = _token;
        admin = _admin;
        treasury = _treasury;
        devAddr = _devAddr;
        latestMintTime = _startMintTime;
    }

    /**
     * @notice Checks if the msg.sender is the admin address
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "admin: wut?");
        _;
    }

    /**
     * @notice Deposits funds into the Arbswap X Token
     * @dev Only possible when contract not paused.
     * @param _amount: number of tokens to deposit (in Arbs)
     */
    function deposit(uint256 _amount) external whenNotPaused {
        depositOperation(_amount, msg.sender);
    }

    /**
     * @notice Deposits funds into the Arbswap X Token to user
     * @dev Only possible when contract not paused.
     * @param _amount: number of tokens to deposit (in Arbs)
     * @param _user: deposit token to user
     */
    function deposit(uint256 _amount, address _user) external whenNotPaused {
        depositOperation(_amount, _user);
    }

    /**
     * @notice Deposit operation
     * @param _amount: number of tokens to deposit (in Arbs)
     * @param _user: deposit token to user
     */
    function depositOperation(uint256 _amount, address _user) internal {
        require(_amount >= MIN_DEPOSIT_AMOUNT, "Deposit amount must be greater than MIN_DEPOSIT_AMOUNT");
        mint();
        uint256 pool = available();
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 currentShares = 0;
        if (totalSupply() != 0) {
            currentShares = (_amount * totalSupply()) / pool;
        } else {
            currentShares = _amount;
        }

        userLastDepositedTime[_user] = block.timestamp;

        _mint(_user, currentShares);

        emit Deposit(_user, _amount, currentShares, block.timestamp);
    }

    /**
     * @notice Withdraws shares from the pool
     * @param _shares: Number of shares to withdraw
     */
    function withdraw(uint256 _shares) public whenNotPaused {
        require(_shares > 0, "Nothing to withdraw");
        require(_shares <= balanceOf(msg.sender), "Withdraw amount exceeds balance");
        mint();

        uint256 currentAmount = (available() * _shares) / totalSupply();
        _burn(msg.sender, _shares);

        uint256 currentWithdrawFee;
        if (block.timestamp < userLastDepositedTime[msg.sender] + withdrawFeePeriod) {
            currentWithdrawFee = (currentAmount * withdrawFee) / 10000;
            token.safeTransfer(treasury, currentWithdrawFee);
            currentAmount -= currentWithdrawFee;
        }

        token.safeTransfer(msg.sender, currentAmount);

        emit Withdraw(msg.sender, currentAmount, _shares, currentWithdrawFee);
    }

    /**
     * @notice Withdraws all shares for a user
     */
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    /**
     * @notice Sets admin address
     * @dev Only callable by the contract owner.
     */
    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Cannot be zero address");
        admin = _admin;
    }

    /**
     * @notice Sets treasury address
     * @dev Only callable by the contract owner.
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Cannot be zero address");
        treasury = _treasury;
    }

    /**
     * @notice Sets dev address
     * @dev Only callable by the contract owner.
     */
    function setDevAddress(address _devAddr) external onlyOwner {
        require(_devAddr != address(0), "Cannot be zero address");
        devAddr = _devAddr;
    }

    /**
     * @notice Sets withdraw fee
     * @dev Only callable by the contract admin.
     */
    function setArbsPerSecond(uint256 _arbsPerSecond) external onlyAdmin {
        require(_arbsPerSecond <= MaxArbsPerSecond, "arbsPerSecond cannot be more than MaxArbsPerSecond");
        arbsPerSecond = _arbsPerSecond;
    }

    /**
     * @notice Sets withdraw fee
     * @dev Only callable by the contract admin.
     */
    function setWithdrawFee(uint256 _withdrawFee) external onlyAdmin {
        require(_withdrawFee <= MAX_WITHDRAW_FEE, "withdrawFee cannot be more than MAX_WITHDRAW_FEE");
        withdrawFee = _withdrawFee;
    }

    /**
     * @notice Sets withdraw fee period
     * @dev Only callable by the contract admin.
     */
    function setWithdrawFeePeriod(uint256 _withdrawFeePeriod) external onlyAdmin {
        require(
            _withdrawFeePeriod <= MAX_WITHDRAW_FEE_PERIOD,
            "withdrawFeePeriod cannot be more than MAX_WITHDRAW_FEE_PERIOD"
        );
        withdrawFeePeriod = _withdrawFeePeriod;
    }

    /**
     * @notice Sets mintable
     * @dev Only callable by the contract admin.
     */
    function setMintable(bool _mintable) external onlyAdmin {
        Mintable = _mintable;
        emit SetMintable(_mintable, block.timestamp);
    }

    /**
     * @notice Withdraw unexpected tokens sent to this contract.
     */
    function inCaseTokensGetStuck(address _token) external onlyAdmin {
        require(_token != address(token), "Token cannot be same as deposit token");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Triggers stopped state
     * @dev Only possible when contract not paused.
     */
    function pause() external onlyAdmin whenNotPaused {
        _pause();
    }

    /**
     * @notice Returns to normal state
     * @dev Only possible when contract is paused.
     */
    function unpause() external onlyAdmin whenPaused {
        _unpause();
    }

    /**
     * @notice Return reward multiplier.
     */
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        if (_from >= _to) {
            return 0;
        }
        return _to - _from;
    }

    /**
     * @notice Calculates the price per share
     */
    function getPricePerFullShare() external view returns (uint256) {
        return totalSupply() == 0 ? 1e18 : (available() * (1e18)) / totalSupply();
    }

    /**
     * @notice Arbswap Token Balance
     * @dev
     */
    function available() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Mint tokens From Arbswap Token Contract
     */
    function mint() internal {
        if (Mintable && block.timestamp > latestMintTime) {
            uint256 multiplier = getMultiplier(latestMintTime, block.timestamp);
            uint256 arbsReward = multiplier * arbsPerSecond;
            latestMintTime = block.timestamp;
            token.mintByStaking(devAddr, arbsReward / 10);
            token.mintByStaking(address(this), arbsReward);
        }
    }
}

