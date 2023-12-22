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
import {IBot} from "./IBot.sol";
import {ILevelHelper} from "./ILevelHelper.sol";
import "./console.sol";

contract GeniBotFactory is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    struct User {
        address account;
        uint256 balance;
        uint256 depositBalance;
        uint256 marginBalance;
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

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public botExecutionFee; // USDC
 
    bytes32 public referralCode; 
    address public implementation;
    ILevelHelper public levelHelper;

    mapping(address => bool) public isBotKeeper;
    mapping(address => User) public users;
    mapping(address => address) public userBots;

    mapping(uint256 => uint256) public userLevelFee;
    mapping(uint256 => uint256) public traderLevelFee;
    mapping(uint256 => uint256) public refLevelFee;

    mapping(address => mapping(address => uint256)) public pendingRevenue;

    mapping(address => mapping(uint256 => bool)) public hasRevertIncreasePosition;

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
    event CreateNewBot(address indexed account, address bot);
    event BotRequestToken(address indexed account, uint256 amount);
    event RevertIncreasePosition(address indexed bot, uint256 index, uint256 amount);

    event BotRequestUpdateBalance(address indexed account, address trader, uint256 amount, uint256 realisedPnl, bool isRealisedPnl);

    event HandleFees(
        address indexed account, 
        address trader,
        uint256 userPnl,
        uint256 systemFee,
        uint256 traderFee,
        uint256 referralFee, 
        uint256 systemFeeAmount,
        uint256 traderFeeAmount,
        uint256 referralFeeAmount
    );

    // Pending revenue is claimed
    event RevenueClaim(address indexed claimer, uint256 amount);

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

        botExecutionFee = 100000; // 1 USDC
        isBotKeeper[msg.sender] = true;
        botStatus = true;
        activeReferral = true;

        implementation = _implementation;
        levelHelper = ILevelHelper(_levelHelper);

        // set level fees init for system fee per trade win
        userLevelFee[0] = 50; // 5%
        userLevelFee[1] = 40; // 4%
        userLevelFee[2] = 30;
        userLevelFee[3] = 20;
        userLevelFee[4] = 10;
        userLevelFee[5] = 0;

        traderLevelFee[0] = 30;  // 3%
        traderLevelFee[1] = 40;
        traderLevelFee[2] = 50;
        traderLevelFee[3] = 60;

        refLevelFee[0] = 300; // 30% of 5% in system fee
        refLevelFee[1] = 500; // 50% of 5% in system fee
        refLevelFee[2] = 600; // 60% of 5% in system fee
    }

    modifier onlyBotContract(address _account) {
        require(msg.sender == userBots[_account], "Not is bot contract");
        _;
    }

    function createNewBot(
        address _refAddress,
        uint256 _fixedMargin,
        uint256 _positionLimit,
        uint256 _takeProfit,
        uint256 _stopLoss
    ) external nonReentrant returns (address bot) {
        require(userBots[msg.sender] == address(0), "BotFactory: Already have bot");
        bot = Clones.clone(implementation);
        IBot(bot).initialize(
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
        
        userBots[msg.sender] = address(bot);

        if (refUsers[msg.sender] == address(0) && _refAddress != address(msg.sender) && _refAddress != address(0)) {
            refUsers[msg.sender] = _refAddress;
            refCount[_refAddress] += 1;
        }

        emit CreateNewBot(msg.sender, address(bot));
    }

    function setBotKeeper(address _account, bool _status) external onlyOwner {
        isBotKeeper[_account] = _status;
    }

    function setEmplementation(address _implementation) external onlyOwner {
        implementation = _implementation;
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

    function setReferralCode(bytes32 _referralCode) external onlyOwner {
        referralCode = _referralCode;
    }

    function getReferralCode() external view returns (bytes32) {
        return referralCode;
    }

    function setApproveToken(address spender, uint256 amount) external onlyOwner {
        IERC20(tokenPlay).approve(spender, amount);
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
        require(userBots[msg.sender] != address(0), "BotFactory: User don't have bot");
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
    function revertIncreasePosition(address _bot, uint256 _index) external onlyOwner {
        require(!hasRevertIncreasePosition[_bot][_index], "BotFactory: position already revert");

        (address account,,,, uint256 amountIn ,,,) = IBot(_bot).getIncreasePositionRequests(_index);
        if (amountIn > 0) {
            IBot(_bot).botFactoryCollectToken(_index);

            User storage user = users[account];
            user.balance += amountIn;
            hasRevertIncreasePosition[_bot][_index] = true;

            emit RevertIncreasePosition(_bot, _index, amountIn);
        }
    }

    function botRequestToken(address _account, uint256 _amount) external nonReentrant onlyBotContract(_account) returns(uint256) {
        require(botStatus, "Bot: bot off");
        User storage user = users[_account];
        
        require((_amount + botExecutionFee) <= user.balance, "CreateIncreasePosition: require _amountIn < user.balance");
        require(user.balance > 0, "CreateIncreasePosition: require user.balance > 0");

        uint256 amount = user.balance >= _amount ? _amount : 0;
        
        if (amount > 0) {
            IERC20(tokenPlay).safeTransfer(address(msg.sender), _amount);
            user.balance -= _amount;
            user.balance -= botExecutionFee;

            pendingRevenue[owner()][tokenPlay] += botExecutionFee;
        }
        emit BotRequestToken(_account, _amount);
        return amount;
    }

    function botRequestUpdateBalance(
        address _account, 
        address _trader, 
        uint256 _amount, 
        uint256 _realisedPnl, 
        bool _isRealisedPnl
    ) external nonReentrant onlyBotContract(_account) returns(uint256) {
        require(botStatus, "Bot: bot off");
        User storage user = users[_account];
        
        if (_amount > 0) {
            user.balance += _amount;
            user.balance -= botExecutionFee;

            pendingRevenue[owner()][tokenPlay] += botExecutionFee;

            if (_isRealisedPnl) {
                user.profitAmount += _getUserPnlAndHandleFees(_account, _trader, _realisedPnl);
                user.revenueAmount += _realisedPnl;
            } else {
                user.lossAmount += _realisedPnl;
            }
        }
        emit BotRequestUpdateBalance(_account, _trader, _amount, _realisedPnl, _isRealisedPnl);
        return _amount;
    }

    function _getUserPnlAndHandleFees(address _account, address _trader, uint256 _realisedPnl) internal returns (uint256 userPnl) {
        address refAddress = refUsers[_account];
        bool hasRefAccount = refAddress != address(0) && activeReferral;

        uint256 systemFee = userLevelFee[levelHelper.getUserLevel(_account)];
        uint256 traderFee = traderLevelFee[levelHelper.getTraderLevel(_trader)];
        uint256 referralFee = 0;

        if (hasRefAccount) {
            referralFee = refLevelFee[levelHelper.getRefLevel(refAddress)];
        }

        uint256 traderFeeAmount = ((traderFee * BASIS_POINTS_DIVISOR / 1000) * _realisedPnl) / BASIS_POINTS_DIVISOR;
        uint256 systemFeeAmount = ((systemFee * BASIS_POINTS_DIVISOR / 1000) * _realisedPnl) / BASIS_POINTS_DIVISOR;
        uint256 referralFeeAmount = ((referralFee * BASIS_POINTS_DIVISOR / 1000) * systemFeeAmount) / BASIS_POINTS_DIVISOR;

        referralFeeAmount = hasRefAccount ? referralFeeAmount : 0;
        userPnl = _realisedPnl - (systemFeeAmount + traderFeeAmount + referralFeeAmount);
        uint256 realSystemFeeAmount = systemFeeAmount - referralFeeAmount;
        
        pendingRevenue[owner()][tokenPlay] += realSystemFeeAmount;
        pendingRevenue[_trader][tokenPlay] += traderFeeAmount;
        pendingRevenue[refAddress][tokenPlay] += referralFeeAmount;

        emit HandleFees(
            _account, 
            _trader, 
            userPnl,
            systemFee,
            traderFee,
            referralFee,
            realSystemFeeAmount,
            traderFeeAmount,
            referralFeeAmount
        );
    }

    function withdrawBalance(uint256 _amount) external nonReentrant {
        require(botStatus, "Bot: bot off");
        require(_amount > 0, "Withdraw: requie amount > 0");
        User storage user = users[msg.sender];
        require(_amount <= user.balance, "Withdraw: requie amount > 0");
        IERC20(tokenPlay).safeTransfer(address(msg.sender), _amount);
        user.balance -= _amount;

        emit Withdraw(msg.sender, _amount);
    }

    /**
     * @notice Allows the owner to recover tokens sent to the contract by mistake
     * @param _token: token address
     * @dev Callable by owner
     */
    function recoverFungibleTokens(address _token) external onlyOwner {
        uint256 amountToRecover = IERC20(_token).balanceOf(address(this));
        require(amountToRecover != 0, "Operations: No token to recover");

        IERC20(_token).safeTransfer(address(msg.sender), amountToRecover);

        emit TokenRecovery(_token, amountToRecover);
    }

    /**
     * @notice Allows the owner to recover NFTs sent to the contract by mistake
     * @param _token: NFT token address
     * @param _tokenId: tokenId
     * @dev Callable by owner
     */
    function recoverNonFungibleToken(address _token, uint256 _tokenId) external onlyOwner nonReentrant {
        IERC721(_token).safeTransferFrom(address(this), address(msg.sender), _tokenId);

        emit NonFungibleTokenRecovery(_token, _tokenId);
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
        uint256 propsLength = 11;

        uint256[] memory rets = new uint256[](bots.length * propsLength);

        for (uint256 i = 0; i < bots.length; i++) {
         (,uint256 fixedMargin,uint256 positionLimit, uint256 takeProfit , uint256 stopLoss, uint256 level)  = IBot(bots[i]).getUser();

            User memory u = users[address(_users[i])];

            rets[i * propsLength + 0] = fixedMargin;
            rets[i * propsLength + 1] = positionLimit;
            rets[i * propsLength + 2] = takeProfit;
            rets[i * propsLength + 3] = stopLoss;
            rets[i * propsLength + 4] = level;
            rets[i * propsLength + 5] = u.balance;
            rets[i * propsLength + 6] = u.depositBalance;
            rets[i * propsLength + 7] = u.marginBalance;
            rets[i * propsLength + 8] = u.profitAmount;
            rets[i * propsLength + 9] = u.lossAmount;
            rets[i * propsLength + 10] = u.revenueAmount;
        }
        return rets;
    }
}
