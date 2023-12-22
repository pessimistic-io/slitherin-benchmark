// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./ERC20.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";

interface IGumBallFactory {
    function getTreasury() external view returns (address);
}

interface IXGBT {
    function balanceOf(address account) external view returns (uint256);
    function notifyRewardAmount(address _rewardsToken, uint256 reward) external; 
}

interface IGBT {
    function getXGBT() external view returns (address);
    function getFactory() external view returns (address);
    function artistTreasury() external view returns (address);
}

contract GBTFees is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address internal immutable _GBT;
    address internal immutable _BASE;
    uint256 public constant TREASURY = 200;
    uint256 public constant GUMBAR = 400;
    uint256 public constant ARTIST = 400;
    uint256 public constant REWARD = 10;
    uint256 public constant DIVISOR = 1000;

    event Distribute(address indexed user);

    constructor(address __GBT, address __BASE) {
        _GBT = __GBT;
        _BASE = __BASE;
    }

    function distributeReward() external view returns (uint256) {
        return IERC20(_BASE).balanceOf(address(this)) * REWARD / DIVISOR;
    }

    function distributeFees() external nonReentrant {
        uint256 balanceGBT = IERC20(_GBT).balanceOf(address(this));
        uint256 balanceBASE = IERC20(_BASE).balanceOf(address(this));

        uint256 reward = balanceBASE * REWARD / DIVISOR;
        balanceBASE -= reward;

        address treasury = IGumBallFactory(IGBT(_GBT).getFactory()).getTreasury();
        address artist = IGBT(_GBT).artistTreasury();
        address _xgbt = IGBT(_GBT).getXGBT();

        // Distribute GBT
        IERC20(_GBT).safeApprove(_xgbt, 0);
        IERC20(_GBT).safeApprove(_xgbt, balanceGBT * GUMBAR / DIVISOR);
        IXGBT(_xgbt).notifyRewardAmount(_GBT, balanceGBT * GUMBAR / DIVISOR);
        IERC20(_GBT).safeTransfer(artist, balanceGBT * ARTIST / DIVISOR);
        IERC20(_GBT).safeTransfer(treasury, balanceGBT * TREASURY / DIVISOR);

        // Distribute BASE
        IERC20(_BASE).safeApprove(_xgbt, 0);
        IERC20(_BASE).safeApprove(_xgbt, balanceBASE * GUMBAR / DIVISOR);
        IXGBT(_xgbt).notifyRewardAmount(_BASE, balanceBASE * GUMBAR / DIVISOR);
        IERC20(_BASE).safeTransfer(artist, balanceBASE * ARTIST / DIVISOR);
        IERC20(_BASE).safeTransfer(treasury, balanceBASE * TREASURY / DIVISOR);
        IERC20(_BASE).safeTransfer(msg.sender, reward);

        emit Distribute(msg.sender);
    }
}

contract GBT is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Bonding Curve Variables
    address public immutable BASE_TOKEN;

    uint256 public immutable reserveVirtualBASE;
    uint256 public reserveRealBASE;
    uint256 public reserveGBT;
    
    uint256 public immutable initial_totalSupply;

    // Addresses
    address public XGBT;
    address public artist;
    address public artistTreasury;
    address public immutable fees; // Fee Contract
    address public immutable factory;

    // Affiliates
    mapping(address => address) public referrals; // account => affiliate

    // Allowlist Variables
    mapping(address => uint256) public allowlist;
    uint256 public immutable start;
    uint256 public immutable delay;
    bool public open;

    // Borrow Variables
    uint256 public borrowedTotalBASE;
    mapping(address => uint256) public borrowedBASE;

    // Fee
    uint256 public immutable fee;
    uint256 public constant AFFILIATE = 100;
    uint256 public constant DIVISOR = 1000;

    // Events
    event Buy(address indexed user, uint256 amount, address indexed affiliate);
    event Sell(address indexed user, uint256 amount, address indexed affiliate);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event AllowListUpdated(address[] accounts, uint256 amount);
    event XGBTSet(address indexed _XGBT);
    event ChangeArtist(address newArtist);
    event ChangeArtistTreasury(address newArtistTreasury);
    event AffiliateSet(address[] indexed affiliate, bool flag);
    event MarketOpened(uint256 _timestamp);

    constructor(
        string memory _name,
        string memory _symbol,
        address _baseToken,
        uint256 _initialVirtualBASE,
        uint256 _supplyGBT,
        address _artist,
        address _factory,
        uint256 _delay,
        uint256 _fee
        ) ERC20(_name, _symbol) {

        require(_fee <= 100, "Redemption fee too high");
        require(_fee >= 25, "Redemption fee too low");
        BASE_TOKEN = _baseToken;
        artist = _artist;
        artistTreasury = _artist;
        factory = _factory;

        reserveVirtualBASE = _initialVirtualBASE;

        reserveRealBASE = 0;
        initial_totalSupply = _supplyGBT;
        reserveGBT = _supplyGBT;

        start = block.timestamp;
        delay = _delay;
        fee = _fee;
        open = false;

        fees = address(new GBTFees(address(this), BASE_TOKEN));
        _mint(address(this), _supplyGBT);

    }

    //////////////////
    ///// Public /////
    //////////////////

    /** @dev returns the current price of {GBT} */
    function currentPrice() external view returns (uint256) {
        return ((reserveVirtualBASE + reserveRealBASE) * 1e18) / reserveGBT;
    }

    /** @dev returns the allowance @param user can borrow */
    function borrowCredit(address account) external view returns (uint256) {
        uint256 borrowPowerGBT = IXGBT(XGBT).balanceOf(account);
        if (borrowPowerGBT == 0) {
            return 0;
        }
        uint256 borrowTotalBASE = (reserveVirtualBASE * totalSupply() / (totalSupply() - borrowPowerGBT)) - reserveVirtualBASE;
        uint256 borrowableBASE = borrowTotalBASE - borrowedBASE[account];
        return borrowableBASE;
    }

    /** @dev returns amount borrowed by @param user */
    function debt(address account) external view returns (uint256) {
        return borrowedBASE[account];
    }

    function baseBal() external view returns (uint256) {
        return IERC20(BASE_TOKEN).balanceOf(address(this));
    }

    function gbtBal() external view returns (uint256) {
        return IERC20(address(this)).balanceOf(address(this));
    }

    function getFactory() external view returns (address) {
        return factory;
    }

    function getXGBT() external view returns (address) {
        return XGBT;
    }

    function getFees() external view returns (address) {
        return fees;
    }

    function getArtist() external view returns (address) {
        return artist;
    }

    function initSupply() external view returns (uint256) {
        return initial_totalSupply;
    }

    function floorPrice() external view returns (uint256) {
        return (reserveVirtualBASE * 1e18) / totalSupply();
    }

    function mustStayGBT(address account) external view returns (uint256) {
        uint256 accountBorrowedBASE = borrowedBASE[account];
        if (accountBorrowedBASE == 0) {
            return 0;
        }
        uint256 amount = totalSupply() - (reserveVirtualBASE * totalSupply() / (accountBorrowedBASE + reserveVirtualBASE));
        return amount;
    }

    ////////////////////
    ///// External /////
    ////////////////////

    /** @dev Buy function.  User spends {BASE} and receives {GBT}
      * @param _amountBASE is the amount of the {BASE} being spent
      * @param _minGBT is the minimum amount of {GBT} out
      * @param expireTimestamp is the expire time on txn
      *
      * If a delay was set on the proxy deployment and has not elapsed:
      *     1. the user must be whitelisted by the protocol to call the function
      *     2. the whitelisted user cannont buy more than 1 GBT until the delay has elapsed
    */
    function buy(uint256 _amountBASE, uint256 _minGBT, uint256 expireTimestamp, address affiliate) external nonReentrant {
        require(expireTimestamp == 0 || expireTimestamp >= block.timestamp, "Expired");
        require(_amountBASE > 0, "Amount cannot be zero");

        address account = msg.sender;
        if (referrals[account] == address(0) && affiliate != address(0)) {
            referrals[account] = affiliate;
        } 

        uint256 feeAmountBASE = _amountBASE * fee / DIVISOR;

        uint256 oldReserveBASE = reserveVirtualBASE + reserveRealBASE;
        uint256 newReserveBASE = oldReserveBASE + _amountBASE - feeAmountBASE;

        uint256 oldReserveGBT = reserveGBT;
        uint256 newReserveGBT = oldReserveBASE * oldReserveGBT / newReserveBASE;

        uint256 outGBT = oldReserveGBT - newReserveGBT;

        require(outGBT > _minGBT, "Less than Min");

        if (start + delay >= block.timestamp) {
            require(open, "Market not open yet");
            require(outGBT <= allowlist[account], "Allowlist amount overflow");
            allowlist[account] -= outGBT;
        }

        reserveRealBASE = newReserveBASE - reserveVirtualBASE;
        reserveGBT = newReserveGBT;

        if (referrals[account] == address(0)) {
            IERC20(BASE_TOKEN).safeTransferFrom(account, fees, feeAmountBASE);
        } else {
            IERC20(BASE_TOKEN).safeTransferFrom(account, referrals[account], feeAmountBASE * AFFILIATE / DIVISOR);
            IERC20(BASE_TOKEN).safeTransferFrom(account, fees, feeAmountBASE - (feeAmountBASE * AFFILIATE / DIVISOR));
        }

        IERC20(BASE_TOKEN).safeTransferFrom(account, address(this), _amountBASE - feeAmountBASE);
        IERC20(address(this)).safeTransfer(account, outGBT);

        emit Buy(account, _amountBASE, referrals[account]); 
    }

    /** @dev Sell function.  User sells their {GBT} token for {BASE}
      * @param _amountGBT is the amount of {GBT} in
      * @param _minETH is the minimum amount of {ETH} out 
      * @param expireTimestamp is the expire time on txn
    */
    function sell(uint256 _amountGBT, uint256 _minETH, uint256 expireTimestamp) external nonReentrant {
        require(expireTimestamp == 0 || expireTimestamp >= block.timestamp, "Expired");
        require(_amountGBT > 0, "Amount cannot be zero");

        address account = msg.sender;

        uint256 feeAmountGBT = _amountGBT * fee / DIVISOR;

        uint256 oldReserveGBT = reserveGBT;
        uint256 newReserveGBT = reserveGBT + _amountGBT - feeAmountGBT;

        uint256 oldReserveBASE = reserveVirtualBASE + reserveRealBASE;
        uint256 newReserveBASE = oldReserveBASE * oldReserveGBT / newReserveGBT;

        uint256 outBASE = oldReserveBASE - newReserveBASE;

        require(outBASE > _minETH, "Less than Min");

        reserveRealBASE = newReserveBASE - reserveVirtualBASE;
        reserveGBT = newReserveGBT;

        if (referrals[account] == address(0)) {
            IERC20(address(this)).safeTransferFrom(account, fees, feeAmountGBT);
        } else {
            IERC20(address(this)).safeTransferFrom(account, referrals[account], feeAmountGBT * AFFILIATE / DIVISOR);
            IERC20(address(this)).safeTransferFrom(account, fees, feeAmountGBT - (feeAmountGBT * AFFILIATE / DIVISOR));
        }

        IERC20(address(this)).safeTransferFrom(account, address(this), _amountGBT - feeAmountGBT);
        IERC20(BASE_TOKEN).safeTransfer(account, outBASE);

        emit Sell(account, _amountGBT, referrals[account]); 
    }

    /** @dev User borrows an amount of {BASE} equal to @param _amount */
    function borrowSome(uint256 _amount) external nonReentrant {
        require(_amount > 0, "!Zero");

        address account = msg.sender;

        uint256 borrowPowerGBT = IXGBT(XGBT).balanceOf(account);

        uint256 borrowTotalBASE = (reserveVirtualBASE * totalSupply() / (totalSupply() - borrowPowerGBT)) - reserveVirtualBASE;
        uint256 borrowableBASE = borrowTotalBASE - borrowedBASE[account];

        require(borrowableBASE >= _amount, "Borrow Underflow");

        borrowedBASE[account] += _amount;
        borrowedTotalBASE += _amount;

        IERC20(BASE_TOKEN).safeTransfer(account, _amount);

        emit Borrow(account, _amount);
    }

    /** @dev User borrows the maximum amount of {BASE} their locked {XGBT} will allow */
    function borrowMax() external nonReentrant {

        address account = msg.sender;

        uint256 borrowPowerGBT = IXGBT(XGBT).balanceOf(account);

        uint256 borrowTotalBASE = (reserveVirtualBASE * totalSupply() / (totalSupply() - borrowPowerGBT)) - reserveVirtualBASE;
        uint256 borrowableBASE = borrowTotalBASE - borrowedBASE[account];

        borrowedBASE[account] += borrowableBASE;
        borrowedTotalBASE += borrowableBASE;

        IERC20(BASE_TOKEN).safeTransfer(account, borrowableBASE);

        emit Borrow(account, borrowableBASE);
    }

    /** @dev User repays a portion of their debt equal to @param _amount */
    function repaySome(uint256 _amount) external nonReentrant {
        require(_amount > 0, "!Zero");

        address account = msg.sender;
        
        borrowedBASE[account] -= _amount;
        borrowedTotalBASE -= _amount;

        IERC20(BASE_TOKEN).safeTransferFrom(account, address(this), _amount);

        emit Repay(account, _amount);
    }

    /** @dev User repays their debt and opens unlocking of {XGBT} */
    function repayMax() external nonReentrant {

        address account = msg.sender;

        uint256 amountRepayBASE = borrowedBASE[account];
        borrowedBASE[account] = 0;
        borrowedTotalBASE -= amountRepayBASE;

        IERC20(BASE_TOKEN).safeTransferFrom(account, address(this), amountRepayBASE);

        emit Repay(account, amountRepayBASE);
    }

    ////////////////////
    //// Restricted ////
    ////////////////////

    function updateAllowlist(address[] memory accounts, uint256 amount) external {
        require(msg.sender == factory || msg.sender == artist, "!AUTH");
        for (uint256 i = 0; i < accounts.length; i++) {
            allowlist[accounts[i]] = amount;
        }
        emit AllowListUpdated(accounts, amount);
    }

    function setXGBT(address _XGBT) external OnlyFactory {
        XGBT = _XGBT;
        emit XGBTSet(_XGBT);
    }

    function setArtist(address _artist) external {
        require(msg.sender == artist, "!AUTH");
        artist = _artist;
        emit ChangeArtist(_artist);
    }

    function setArtistTreasury(address _artistTreasury) external {
        require(msg.sender == artist, "!AUTH");
        artistTreasury = _artistTreasury;
        emit ChangeArtistTreasury(_artistTreasury);
    }

    function openMarket() external {
        require(msg.sender == artist, "!AUTH");
        open = true;
        emit MarketOpened(block.timestamp);
    }

    modifier OnlyFactory() {
        require(msg.sender == factory, "!AUTH");
        _;
    }
}

contract GBTFactory {
    address public factory;
    address public lastGBT;

    event FactorySet(address indexed _factory);

    constructor() {
        factory = msg.sender;
    }

    function setFactory(address _factory) external OnlyFactory {
        factory = _factory;
        emit FactorySet(_factory);
    }

    function createGBT(
        string memory _name,
        string memory _symbol,
        address _baseToken,
        uint256 _initialVirtualBASE,
        uint256 _supplyGBT,
        address _artist,
        address _factory,
        uint256 _delay,
        uint256 _fee
    ) external OnlyFactory returns (address) {
        GBT newGBT = new GBT(_name, _symbol, _baseToken, _initialVirtualBASE, _supplyGBT, _artist, _factory, _delay, _fee);
        lastGBT = address(newGBT);
        return lastGBT;
    }

    modifier OnlyFactory() {
        require(msg.sender == factory, "!AUTH");
        _;
    }
}
