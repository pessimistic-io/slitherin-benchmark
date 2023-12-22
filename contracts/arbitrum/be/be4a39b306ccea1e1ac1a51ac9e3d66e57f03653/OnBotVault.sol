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
import {IOnBot} from "./IOnBot.sol";
import {IWETH} from "./IWETH.sol";

contract OnBotVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct User {
        address account;
        uint256 balance;
        uint256 depositBalance;
    }

    bool public botStatus;
    bool public activeReferral;
    address public tokenPlay;
    address public positionRouter;
    address public vault;
    address public router;
    address public weth;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public marginFeeBasisPoints = 10; // 0.1%

    uint256 public botExecutionFee; // USDC
 
    bytes32 public referralCode;

    mapping(uint256 => address) public implementations;
    mapping(address => EnumerableSet.AddressSet) private _userBots;

    mapping(address => bool) public isBotKeeper;
    mapping(address => User) public users;

    uint256 public userLevelFee;
    uint256 public refLevelFee;

    mapping(address => mapping(address => uint256)) public pendingRevenue;

    mapping(address => address) public refUsers;
    mapping(address => uint256) public refCount;

    // Recover NFT tokens sent by accident
    event NonFungibleTokenRecovery(address indexed token, uint256 indexed tokenId);

    // Recover ERC20 tokens sent by accident
    event TokenRecovery(address indexed token, uint256 amount);

    event SetBotStatus(bool status);
    event SetActiveReferral(bool status);
    event Deposit(address indexed account, address tokenAddress, uint256 amount, address refAddress);
    event Withdraw(address indexed account, uint256 amount); 
    event TransferBalance(address indexed account, uint256 amount); 
    event CreateNewBot(address indexed account, address bot);
    event BotRequestToken(address indexed account, uint256 amount, address botAddress, uint256 botExecutionFee);
    event CollectToken(address indexed user, address bot, uint256 amount);
    event SetBotExecutionFee(uint256 botExecutionFee);

    event BotRequestUpdateBalanceAndFees(
        address indexed account, 
        address trader, 
        uint256 amount, 
        uint256 realisedPnl, 
        bool isRealisedPnl, 
        address botAddress,
        uint256 onbotFees,
        uint256 botExecutionFee
    );

    event BotRequestUpdateFees(
        address indexed account, 
        address trader,
        uint256 realisedPnl, 
        bool isRealisedPnl, 
        address botAddress,
        uint256 onbotFees,
        uint256 botExecutionFee
    );

    event BotRequestUpdateBalance(
        address indexed account, 
        uint256 amount,
        address botAddress
    );

    event HandleRefAndSystemFees(
        address indexed bot,
        uint256 systemFeeAmount, 
        address referrer,
        uint256 referralFeeAmount
    );

    // Pending revenue is claimed
    event RevenueClaim(address indexed claimer, uint256 amount);
    event TakeFee(address indexed account, address owner, uint256 amount);

    constructor(
        address _implementation
    ) {
        tokenPlay = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC, decimals 6
        weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

        positionRouter = 0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868;
        vault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
        router = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064;

        botExecutionFee = 800000; // 0.8 USDC
        isBotKeeper[msg.sender] = true;
        botStatus = true;
        activeReferral = true;

        implementations[0] = _implementation;

        // set level fees init for system fee per trade win
        userLevelFee = 300; // 300 3%
        refLevelFee = 3300; // 3300 33% of 3% in system fee
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
        address _user
    ) external nonReentrant onlyBotKeeper returns (address bot) {
        require(implementations[_implementationNo] != address(0), "createNewBot: require implementation");

        bot = Clones.clone(implementations[_implementationNo]);
        IOnBot(bot).initialize(
            tokenPlay, 
            positionRouter, 
            vault, 
            router, 
            address(this), 
            _user
        );
        
        _userBots[_user].add(address(bot));

        emit CreateNewBot(_user, address(bot));
    }

    function setBotKeeper(address _account, bool _status) external onlyOwner {
        isBotKeeper[_account] = _status;
    }

    function setGmxAddress(address _positionRouter, address _vault, address _router) external onlyOwner {
        positionRouter = _positionRouter;
        vault = _vault;
        router = _router;
    }

    function setMarginFeeBasisPoints(uint256 _number) external onlyOwner {
        marginFeeBasisPoints = _number;
    }

    function getMarginFeeBasisPoints() view external returns (uint256) {
        return marginFeeBasisPoints;
    }

    function setEmplementations(uint256 _implementationNo, address _implementation) external onlyOwner {
        implementations[_implementationNo] = _implementation;
    }

    function getBotKeeper(address _account) external view returns (bool) {
        return isBotKeeper[_account];
    }
    
    // USDC fee
    function setBotExecutionFee(uint256 _botExecutionFee) external onlyOwner {
        botExecutionFee = _botExecutionFee;
        emit SetBotExecutionFee(_botExecutionFee);
    }

    function setUserLevelFee(uint256 _fee) external onlyOwner {
        userLevelFee = _fee;
    }

    function setRefLevelFee(uint256 _fee) external onlyOwner {
        refLevelFee = _fee;
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

    function getRefLevelFee() external view returns (uint256) {
        return refLevelFee;
    }

    function setBotStatus(bool _status) external onlyOwner {
        botStatus = _status;
        emit SetBotStatus(_status);
    }

    function setActiveReferral(bool _status) external onlyOwner {
        activeReferral = _status;
        emit SetActiveReferral(_status);
    }

    function deposit(address _tokenAddress, uint256 _amount, address _refAddress) external nonReentrant {
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

        if (refUsers[msg.sender] == address(0) && _refAddress != address(msg.sender) && _refAddress != address(0)) {
            refUsers[msg.sender] = _refAddress;
        }

        emit Deposit(msg.sender, _tokenAddress, amount, _refAddress);
    }

    function depositETH(address _refAddress) payable external nonReentrant {
        require(botStatus, "Bot: bot off");
        require(msg.value > 0, "BotFactory: Deposit requie amount > 0");

        _transferETHToVault();
        uint256 usdcAmount = IVault(vault).swap(weth, tokenPlay, address(this));

        User storage user = users[msg.sender];

        user.account = msg.sender;
        user.balance += usdcAmount;
        user.depositBalance += usdcAmount;

        if (refUsers[msg.sender] == address(0) && _refAddress != address(msg.sender) && _refAddress != address(0)) {
            refUsers[msg.sender] = _refAddress;
        }

        emit Deposit(msg.sender, weth, usdcAmount, _refAddress);
    }

    function _transferETHToVault() private {
        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).safeTransfer(vault, msg.value);
    }

    // revert trade if GMX cancel increase position
    function collectToken(address _user, address _bot) external nonReentrant onlyBotKeeper {
        require(_userBots[_user].contains(_bot), "collectToken: invalid user or bot");
        uint256 amount = IOnBot(_bot).botFactoryCollectToken();
        
        User storage user = users[_user];
        user.balance += amount;

        emit CollectToken(_user, _bot, amount);
    }

    function botRequestToken(address _account, uint256 _amount) external nonReentrant onlyBotContract(_account) returns(uint256) {
        require(botStatus, "Bot: bot off");
        User storage user = users[_account]; 
        require((_amount + botExecutionFee) <= user.balance, "CreateIncreasePosition: require _amountIn < user.balance");
        
        if (_amount > 0) {
            user.balance -= _amount;
            user.balance -= botExecutionFee;
            pendingRevenue[owner()][tokenPlay] += botExecutionFee;

            IERC20(tokenPlay).safeTransfer(address(msg.sender), _amount);
        }
        emit BotRequestToken(_account, _amount, msg.sender, botExecutionFee);
        return _amount;
    }

    function botRequestUpdateBalanceAndFees(
        address _account, 
        address _trader, 
        uint256 _amount, 
        uint256 _realisedPnl, 
        bool _isRealisedPnl
    ) external nonReentrant onlyBotContract(_account) returns(uint256 onbotFees) {
        User storage user = users[_account];
        
        if (_amount > 0) {
            user.balance -= botExecutionFee;
            pendingRevenue[owner()][tokenPlay] += botExecutionFee;

            if (_isRealisedPnl) {
                (uint256 referralFeeAmount, uint256 systemFeeAmount) = _handleRefAndSystemFees(_account, _realisedPnl, msg.sender);
                onbotFees = referralFeeAmount + systemFeeAmount;
                
                user.balance += _amount - onbotFees;
            } else {
                user.balance += _amount;
            }
        }
        emit BotRequestUpdateBalanceAndFees(_account, _trader, _amount, _realisedPnl, _isRealisedPnl, msg.sender, onbotFees, botExecutionFee);
    }

    function botRequestUpdateBalance(
        address _account, 
        uint256 _amount
    ) external nonReentrant onlyBotContract(_account) {
        User storage user = users[_account];

        if (_amount > 0) {
            user.balance += _amount;
            emit BotRequestUpdateBalance(_account, _amount, msg.sender);
        }
    }

    function botRequestUpdateFees(
        address _account, 
        address _trader,
        uint256 _realisedPnl,  // amount USDC
        bool _isRealisedPnl
    ) external nonReentrant onlyBotContract(_account) returns(uint256 onbotFees) {
        User storage user = users[_account];
        
        user.balance -= botExecutionFee;
        pendingRevenue[owner()][tokenPlay] += botExecutionFee;

        if (_isRealisedPnl) {
            (uint256 referralFeeAmount, uint256 systemFeeAmount) = _handleRefAndSystemFees(_account, _realisedPnl, msg.sender);
            onbotFees = referralFeeAmount + systemFeeAmount;
        
            user.balance -= onbotFees;
        }

        emit BotRequestUpdateFees(_account, _trader, _realisedPnl, _isRealisedPnl, msg.sender, onbotFees, botExecutionFee);
    }

    function _handleRefAndSystemFees(address _account, uint256 _realisedPnl, address _botAddress) internal returns (uint256 referralFeeAmount, uint256 systemFeeAmount) {
        address refAddress = refUsers[_account];

        bool hasRefAccount = refAddress != address(0) && activeReferral;
        uint256 referralFee = 0;
        
        if (hasRefAccount) {
            referralFee = refLevelFee;
        }

        systemFeeAmount = userLevelFee * _realisedPnl / BASIS_POINTS_DIVISOR;
        referralFeeAmount = referralFee * systemFeeAmount / BASIS_POINTS_DIVISOR;
        referralFeeAmount = hasRefAccount ? referralFeeAmount : 0;        
        systemFeeAmount = systemFeeAmount - referralFeeAmount;

        pendingRevenue[owner()][tokenPlay] += systemFeeAmount;

        if (hasRefAccount) {
            pendingRevenue[refAddress][tokenPlay] += referralFeeAmount;
        }

        emit HandleRefAndSystemFees(
            _botAddress,
            systemFeeAmount, 
            refAddress,
            referralFeeAmount
        );
    }

    function withdrawBalance(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Withdraw: requie amount > 0");
        User storage user = users[msg.sender];
        require(_amount <= user.balance, "Withdraw: insufficient balance");

        user.balance -= _amount;
        IERC20(tokenPlay).safeTransfer(address(msg.sender), _amount);

        emit Withdraw(msg.sender, _amount);
    }

    function transferBalance(uint256 _amount, address _to) external nonReentrant {
        require(botStatus, "Bot: bot off");
        require(_amount > 0, "Withdraw: requie amount > 0");
        User storage user = users[msg.sender];
        require(_amount <= user.balance, "Withdraw: insufficient balance");

        user.balance -= _amount;
        IERC20(tokenPlay).safeTransfer(_to, _amount);

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
         (,uint256 fixedMargin,uint256 positionLimit, uint256 takeProfit , uint256 stopLoss, uint256 level)  = IOnBot(bots[i]).getUser();

            User memory u = users[address(_users[i])];

            rets[i * propsLength + 0] = fixedMargin;
            rets[i * propsLength + 1] = positionLimit;
            rets[i * propsLength + 2] = takeProfit;
            rets[i * propsLength + 3] = stopLoss;
            rets[i * propsLength + 4] = level;
            rets[i * propsLength + 5] = u.balance;
            rets[i * propsLength + 6] = u.depositBalance;
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
