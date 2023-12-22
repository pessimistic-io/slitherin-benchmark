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
    address public tokenPlay;
    address public positionRouter;
    address public vault;
    address public router;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public botExecutionFee; // USDC
    uint256 public systemFee = 5; // 5%
    uint256 public traderFee = 3; // 3%
    uint256 public referralFee = 3; // 3%
 
    bytes32 public referralCode; 
    address public implementation;

    mapping (address => bool) public isBotKeeper;
    mapping (address => User) public users;
    mapping (address => address) public userBots;

    mapping(address => mapping(address => uint256)) public pendingRevenue;

    mapping(address => mapping(uint256 => bool)) public hasRevertIncreasePosition;

    mapping(address => address) public refUsers;
    mapping(address => uint256) public refCount;

    // Recover NFT tokens sent by accident
    event NonFungibleTokenRecovery(address indexed token, uint256 indexed tokenId);

    // Recover ERC20 tokens sent by accident
    event TokenRecovery(address indexed token, uint256 amount);

    event SetBotStatus(bool status);
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
        address _implementation
    ) {
        tokenPlay = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC, decimals 6

        positionRouter = _positionRouter;
        vault = _vault;
        router = _router;

        botExecutionFee = 1000000; // 1 USDC
        isBotKeeper[msg.sender] = true;
        botStatus = true;
        implementation = _implementation;
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

    function getBotKeeper(address _account) external view returns (bool) {
        return isBotKeeper[_account];
    }
    
    // USDC fee
    function setBotExecutionFee(uint256 _botExecutionFee) external onlyOwner {
        botExecutionFee = _botExecutionFee;
    }

    function setFee(uint256 _systemFee, uint256 _traderFee, uint256 _referralFee) external onlyOwner {
        systemFee = _systemFee;
        traderFee = _traderFee;
        referralFee = _referralFee;
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

    function deposit(address _tokenAddress, uint256 _amount) external nonReentrant {
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
        bool hasRefAccount = refUsers[_account] != address(0);

        uint256 systemFeeWithRef = hasRefAccount ? (systemFee - referralFee) : systemFee;
        uint256 systemFeeAmount = ((systemFeeWithRef * BASIS_POINTS_DIVISOR / 100) * _realisedPnl) / BASIS_POINTS_DIVISOR;
        uint256 traderFeeAmount = ((traderFee * BASIS_POINTS_DIVISOR / 100) * _realisedPnl) / BASIS_POINTS_DIVISOR;
        uint256 referralFeeAmount = ((referralFee * BASIS_POINTS_DIVISOR / 100) * _realisedPnl) / BASIS_POINTS_DIVISOR;

        referralFeeAmount = hasRefAccount ? referralFeeAmount : 0;
        userPnl = _realisedPnl - (systemFeeAmount + traderFeeAmount + referralFeeAmount);
        
        pendingRevenue[owner()][tokenPlay] += systemFeeAmount;
        pendingRevenue[_trader][tokenPlay] += traderFeeAmount;
        pendingRevenue[refUsers[_account]][tokenPlay] += referralFeeAmount;

        emit HandleFees(
            _account, 
            _trader, 
            userPnl, 
            systemFeeAmount,
            traderFeeAmount,
            referralFeeAmount
        );
    }

    function withdrawBalance(uint256 _amount) external nonReentrant {
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
