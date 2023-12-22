// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./Context.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./EnumerableSet.sol";
import "./IERC20.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./IERC721.sol";
import "./Clones.sol";

import {IPositionRouter} from "./IPositionRouter.sol";
import {IVault} from "./IVault.sol";
import {IRouter} from "./IRouter.sol";
import {IGeniBot} from "./IGeniBot.sol";
import {ILevelHelper} from "./ILevelHelper.sol";

contract GeniVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct User {
        address account;
        uint256 balance;
        uint256 depositBalance;
        uint256 profitAmount;
        uint256 lossAmount;
        uint256 revenueAmount;
    }

    bool public botStatus;
    bool public activeReferral;
    address public tokenPlay;
    address public positionRouter;
    address public vault;
    address public router;

    uint256 public maxBotPerUser = 5;
    uint256 public countBotRequireFee = 3;
    uint256 public createBotFee = 10000000; // 100 USDC if > countBotRequireFee

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public botExecutionFee; // USDC
 
    bytes32 public referralCode; 
    ILevelHelper public levelHelper;

    mapping(uint256 => address) public implementations;
    mapping(address => EnumerableSet.AddressSet) private _userBots;

    mapping(address => bool) public isBotKeeper;
    mapping(address => User) public users;

    mapping(uint256 => uint256) public userLevelFee;
    mapping(uint256 => uint256) public traderLevelFee;
    mapping(uint256 => uint256) public refLevelFee;
    mapping(uint256 => uint256) public ref2LevelFee;

    mapping(address => mapping(address => uint256)) public pendingRevenue;

    mapping(address => address) public refUsers;
    mapping(address => uint256) public refCount;

    // Recover NFT tokens sent by accident
    event NonFungibleTokenRecovery(address indexed token, uint256 indexed tokenId);

    // Recover ERC20 tokens sent by accident
    event TokenRecovery(address indexed token, uint256 amount);

    event SetBotStatus(bool status);
    event SetActiveReferral(bool status);
    event Deposit(address indexed account, address tokenAddress, uint256 amount);
    event Withdraw(address indexed account, uint256 amount); 
    event TransferBalance(address indexed account, uint256 amount); 
    event CreateNewBot(address indexed account, address bot, address refAddress, uint256 fixedMargin, uint256 positionLimit, uint256 takeProfit, uint256 stopLoss);
    event BotRequestToken(address indexed account, uint256 amount, address botAddress);
    event CollectToken(address indexed user, address bot, uint256 amount);

    event BotRequestUpdateBalance(
        address indexed account, 
        address trader, 
        uint256 amount, 
        uint256 realisedPnl, 
        bool isRealisedPnl, 
        address botAddress,
        uint256 totalFee
    );

    event HandleRefAndSystemFees(
        address indexed bot,
        uint256 systemFeeAmount, 
        address referrerLv1,
        uint256 referralFeeAmount,
        address referrerLv2,
        uint256 referral2FeeAmount
    );

    event HandleTraderFees(
        address indexed bot,
        address trader, 
        uint256 traderFeeAmount
    );

    // Pending revenue is claimed
    event RevenueClaim(address indexed claimer, uint256 amount);

    event TakeFee(address indexed owner, uint256 amount);

    constructor(
        address _positionRouter,
        address _vault,
        address _router,
        address _implementation,
        address _levelHelper
    ) {
        tokenPlay = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC, decimals 6

        positionRouter = _positionRouter;
        vault = _vault;
        router = _router;

        botExecutionFee = 50000; // 0.5 USDC
        isBotKeeper[msg.sender] = true;
        botStatus = true;
        activeReferral = true;

        implementations[0] = _implementation;
        levelHelper = ILevelHelper(_levelHelper);

        // set level fees init for system fee per trade win
        userLevelFee[0] = 500; // 5%
        userLevelFee[1] = 400; // 4%
        userLevelFee[2] = 300;
        userLevelFee[3] = 200;
        userLevelFee[4] = 100;
        userLevelFee[5] = 0;

        traderLevelFee[0] = 300;  // 3%
        traderLevelFee[1] = 400;
        traderLevelFee[2] = 500;
        traderLevelFee[3] = 600;

        refLevelFee[0] = 3000; // 30% of 5% in system fee
        refLevelFee[1] = 4000; // 40% of 5% in system fee
        refLevelFee[2] = 5000; // 50% of 5% in system fee

        ref2LevelFee[0] = 500; // 5% of 5% in system fee
        ref2LevelFee[1] = 800; // 8% of 5% in system fee
        ref2LevelFee[2] = 1000; // 10% of 5% in system fee
    }

    modifier onlyBotContract(address _account) {
        require(_userBots[_account].contains(msg.sender), "onlyBotContract: Is not bot contract");
        _;
    }

    modifier onlyBotKeeper() {
        require(isBotKeeper[msg.sender], "onlyBotKeeper: Is not keeper");
        _;
    }

    function createNewBot(
        uint256 _implementationNo,
        address _refAddress,
        uint256 _fixedMargin,
        uint256 _positionLimit,
        uint256 _takeProfit,
        uint256 _stopLoss
    ) external nonReentrant returns (address bot) {
        uint256 count = _userBots[msg.sender].length();
        require(count < maxBotPerUser, "createNewBot: need less than max bot per user");
        require(implementations[_implementationNo] != address(0), "createNewBot: require implementation");

        if (count >= countBotRequireFee) {
            User memory user = users[msg.sender];
            require(user.balance >= createBotFee, "createNewBot: not enough fee");
            _takeFee(msg.sender, createBotFee);
        }

        bot = Clones.clone(implementations[_implementationNo]);
        IGeniBot(bot).initialize(
            tokenPlay, 
            positionRouter, 
            vault, 
            router, 
            address(this), 
            msg.sender, 
            _fixedMargin, 
            _positionLimit, 
            _takeProfit, 
            _stopLoss
        );
        
        _userBots[msg.sender].add(address(bot));

        if (refUsers[msg.sender] == address(0) && _refAddress != address(msg.sender) && _refAddress != address(0)) {
            refUsers[msg.sender] = _refAddress;
            refCount[_refAddress] += 1;
        }

        emit CreateNewBot(msg.sender, address(bot), _refAddress, _fixedMargin, _positionLimit, _takeProfit, _stopLoss);
    }

    function _takeFee(address _account, uint256 _fee) internal {
        User storage user = users[_account];
        require(user.balance >= _fee, "Take fee: not enough balance");

        user.balance -= _fee;
        pendingRevenue[owner()][tokenPlay] += _fee;
        emit TakeFee(owner(), _fee);
    }

    function setBotKeeper(address _account, bool _status) external onlyOwner {
        isBotKeeper[_account] = _status;
    }

    function setGmxAddress(address _positionRouter, address _vault, address _router) external onlyOwner {
        positionRouter = _positionRouter;
        vault = _vault;
        router = _router;
    }

    function setMaxBotPerUser(uint256 _maxBot) external onlyOwner {
        maxBotPerUser = _maxBot;
    }

    function setCountBotRequireFee(uint256 _count) external onlyOwner {
        countBotRequireFee = _count;
    }

    function setCreateBotFee(uint256 _fee) external onlyOwner {
        createBotFee = _fee;
    }

    function setEmplementations(uint256 _implementationNo, address _implementation) external onlyOwner {
        implementations[_implementationNo] = _implementation;
    }

    function setLevelHelper(address _levelHelper) external onlyOwner {
        levelHelper = ILevelHelper(_levelHelper);
    }

    function getBotKeeper(address _account) external view returns (bool) {
        return isBotKeeper[_account];
    }
    
    // USDC fee
    function setBotExecutionFee(uint256 _botExecutionFee) external onlyOwner {
        botExecutionFee = _botExecutionFee;
    }

    function setUserLevelFee(uint256 _level, uint256 _fee) external onlyOwner {
        userLevelFee[_level] = _fee;
    }

    function setTraderLevelFee(uint256 _level, uint256 _fee) external onlyOwner {
        traderLevelFee[_level] = _fee;
    }

    function setRefLevelFee(uint256 _level, uint256 _fee) external onlyOwner {
        refLevelFee[_level] = _fee;
    }

    function setRef2LevelFee(uint256 _level, uint256 _fee) external onlyOwner {
        ref2LevelFee[_level] = _fee;
    }

    function setReferralCode(bytes32 _referralCode) external onlyOwner {
        referralCode = _referralCode;
    }

    function getReferralCode() external view returns (bytes32) {
        return referralCode;
    }

    function getReferrer(address _user) external view returns (address) {
        return refUsers[_user];
    }

    function getRefLevelFee(address _referrer) external returns (uint256) {
        return refLevelFee[levelHelper.getRefLevel(_referrer)];
    }

    function getRef2LevelFee(address _referrer) external returns (uint256) {
        return ref2LevelFee[levelHelper.getRefLevel(_referrer)];
    }

    function setBotStatus(bool _status) external onlyOwner {
        botStatus = _status;
        emit SetBotStatus(_status);
    }

    function setActiveReferral(bool _status) external onlyOwner {
        activeReferral = _status;
        emit SetActiveReferral(_status);
    }

    function deposit(address _tokenAddress, uint256 _amount) external nonReentrant {
        require(botStatus, "Bot: bot off");
        require(_amount > 0, "BotFactory: Deposit requie amount > 0");

        IERC20(_tokenAddress).safeTransferFrom(address(msg.sender), address(this), _amount);

        uint256 amount;
        if (_tokenAddress == tokenPlay) {
            amount = _amount;
        } else {
            IERC20(_tokenAddress).safeTransfer(vault, _amount);
            amount = IVault(vault).swap(_tokenAddress, tokenPlay, address(this));
        }

        User storage user = users[msg.sender];

        user.account = msg.sender;
        user.balance += amount;
        user.depositBalance += amount;

        emit Deposit(msg.sender, _tokenAddress, amount);
    }

    // revert trade if GMX cancel increase position
    function collectToken(address _user, address _bot) external onlyBotKeeper {
        require(_userBots[_user].contains(_bot), "collectToken: invalid user or bot");
        uint256 amount = IGeniBot(_bot).botFactoryCollectToken();
        
        User storage user = users[_user];
        user.balance += amount;

        emit CollectToken(_user, _bot, amount);
    }

    function botRequestToken(address _account, uint256 _amount, address _botAddress) external nonReentrant onlyBotContract(_account) returns(uint256) {
        require(botStatus, "Bot: bot off");
        User storage user = users[_account]; 
        require((_amount + botExecutionFee) <= user.balance, "CreateIncreasePosition: require _amountIn < user.balance");
        
        if (_amount > 0) {
            IERC20(tokenPlay).safeTransfer(address(msg.sender), _amount);
            user.balance -= _amount;
            user.balance -= botExecutionFee;

            pendingRevenue[owner()][tokenPlay] += botExecutionFee;
        }
        emit BotRequestToken(_account, _amount, _botAddress);
        return _amount;
    }

    function botRequestUpdateBalance(
        address _account, 
        address _trader, 
        uint256 _amount, 
        uint256 _realisedPnl, 
        bool _isRealisedPnl,
        address _botAddress
    ) external nonReentrant onlyBotContract(_account) returns(uint256) {
        require(botStatus, "Bot: bot off");
        User storage user = users[_account];
        
        uint256 totalFee;
        if (_amount > 0) {
            user.balance -= botExecutionFee;
            pendingRevenue[owner()][tokenPlay] += botExecutionFee;

            if (_isRealisedPnl) {
                (uint256 referralFeeAmount, uint256 systemFeeAmount) = _handleRefAndSystemFees(_account, _realisedPnl, _botAddress);
                uint256 traderFeeAmount = _handleTraderFees(_trader, _realisedPnl, _botAddress);
                totalFee = referralFeeAmount + systemFeeAmount + traderFeeAmount;
                uint256 userProfit = _realisedPnl - totalFee;

                user.profitAmount += userProfit;
                user.revenueAmount += _realisedPnl;
                user.balance += _amount - totalFee;
            } else {
                user.balance += _amount;
                user.lossAmount += _realisedPnl;
            }
        }
        emit BotRequestUpdateBalance(_account, _trader, _amount, _realisedPnl, _isRealisedPnl, _botAddress, totalFee);
        return _amount;
    }

    function _handleRefAndSystemFees(address _account, uint256 _realisedPnl, address _botAddress) internal returns (uint256 referralFeeAmount, uint256 systemFeeAmount) {
        address refAddress = refUsers[_account]; // ref level 1
        address ref2Address = refUsers[refAddress]; // ref level 2
        bool hasRefAccount = refAddress != address(0) && activeReferral;
        bool hasRef2Account = ref2Address != address(0) && activeReferral;

        uint256 systemFee = userLevelFee[levelHelper.getUserLevel(_account)];
        uint256 referralFee = 0;
        uint256 referral2Fee = 0;
        if (hasRefAccount) {
            referralFee = refLevelFee[levelHelper.getRefLevel(refAddress)];
            if (hasRef2Account) {
                referral2Fee = ref2LevelFee[levelHelper.getRefLevel(ref2Address)];
            }
        }

        systemFeeAmount = systemFee * _realisedPnl / BASIS_POINTS_DIVISOR;
        uint256 referral1FeeAmount = referralFee * systemFeeAmount / BASIS_POINTS_DIVISOR;
        uint256 referral2FeeAmount = referral2Fee * systemFeeAmount / BASIS_POINTS_DIVISOR;

        referral1FeeAmount = hasRefAccount ? referral1FeeAmount : 0;
        referral2FeeAmount = hasRef2Account ? referral2FeeAmount : 0;
        
        referralFeeAmount = referral1FeeAmount + referral2FeeAmount;
        systemFeeAmount = systemFeeAmount - referralFeeAmount;

        pendingRevenue[owner()][tokenPlay] += systemFeeAmount;

        if (hasRefAccount) {
            pendingRevenue[refAddress][tokenPlay] += referral1FeeAmount;
        }
        if (hasRef2Account) {
            pendingRevenue[ref2Address][tokenPlay] += referral2FeeAmount;
        }

        emit HandleRefAndSystemFees(
            _botAddress,
            systemFeeAmount, 
            refAddress,
            referralFeeAmount,
            ref2Address,
            referral2FeeAmount
        );
    }

    function _handleTraderFees(address _trader, uint256 _realisedPnl, address _botAddress) internal returns (uint256 traderFeeAmount) {
        uint256 traderFee = traderLevelFee[levelHelper.getTraderLevel(_trader)];
        traderFeeAmount = traderFee * _realisedPnl / BASIS_POINTS_DIVISOR;
        pendingRevenue[_trader][tokenPlay] += traderFeeAmount;

        emit HandleTraderFees(
            _botAddress,
            _trader, 
            traderFeeAmount
        );
    }

    function withdrawBalance(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Withdraw: requie amount > 0");
        User storage user = users[msg.sender];
        require(_amount <= user.balance, "Withdraw: insufficient balance");

        IERC20(tokenPlay).safeTransfer(address(msg.sender), _amount);
        user.balance -= _amount;

        emit Withdraw(msg.sender, _amount);
    }

    function transferBalance(uint256 _amount, address _to) external nonReentrant {
        require(botStatus, "Bot: bot off");
        require(_amount > 0, "Withdraw: requie amount > 0");
        User storage user = users[msg.sender];
        require(_amount <= user.balance, "Withdraw: insufficient balance");

        IERC20(tokenPlay).safeTransfer(_to, _amount);
        user.balance -= _amount;

        emit TransferBalance(_to, _amount);
    }

    /**
     * @notice Claim pending revenue
     */
    function claimPendingRevenue(address _token) external nonReentrant {
        require(botStatus, "Bot: bot off");
        uint256 revenueToClaim = pendingRevenue[msg.sender][_token];
        require(revenueToClaim != 0, "Claim: Nothing to claim");
        pendingRevenue[msg.sender][_token] = 0;

        IERC20(_token).safeTransfer(address(msg.sender), revenueToClaim);

        emit RevenueClaim(msg.sender, revenueToClaim);
    }

    function getBots(address[] memory bots, address[] memory _users) public view returns (uint256[] memory) {
        uint256 propsLength = 10;

        uint256[] memory rets = new uint256[](bots.length * propsLength);

        for (uint256 i = 0; i < bots.length; i++) {
         (,uint256 fixedMargin,uint256 positionLimit, uint256 takeProfit , uint256 stopLoss, uint256 level)  = IGeniBot(bots[i]).getUser();

            User memory u = users[address(_users[i])];

            rets[i * propsLength + 0] = fixedMargin;
            rets[i * propsLength + 1] = positionLimit;
            rets[i * propsLength + 2] = takeProfit;
            rets[i * propsLength + 3] = stopLoss;
            rets[i * propsLength + 4] = level;
            rets[i * propsLength + 5] = u.balance;
            rets[i * propsLength + 6] = u.depositBalance;
            rets[i * propsLength + 7] = u.profitAmount;
            rets[i * propsLength + 8] = u.lossAmount;
            rets[i * propsLength + 9] = u.revenueAmount;
        }
        return rets;
    }

    function viewUserBots(
        address user,
        uint256 cursor,
        uint256 size
    )
        external
        view
        returns (
            address[] memory bots
        )
    {
        uint256 length = size;

        if (length > _userBots[user].length() - cursor) {
            length = _userBots[user].length() - cursor;
        }

        bots = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            bots[i] = _userBots[user].at(cursor + i);
        }

        return bots;
    }
}
