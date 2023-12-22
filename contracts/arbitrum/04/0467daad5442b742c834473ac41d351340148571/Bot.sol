// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Context.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./EnumerableSet.sol";
import "./IERC20.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./IERC721.sol";

import "./IPositionRouter.sol";
import "./IVault.sol";
import "./IRouter.sol";
import "./console.sol";

contract Bot is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    struct User {
        address account;
        uint256 balance;
        uint256 depositBalance;
        uint256 marginBalance;
        uint256 leverage;
        uint256 stopLoss;
        uint256 takeProfit;
        uint256 level;
    }

    struct IncreasePositionRequest {
        address account;
        bytes32 requestKey;
        uint256 botFee;
        address[] path;
        address indexToken;
        uint256 amountIn;
        uint256 minOut;
        uint256 sizeDelta;
        bool isLong;
        uint256 acceptablePrice;
        uint256 executionFee;
    }

    struct DecreasePositionRequest {
        address account;
        uint256 botFee;
        address[] path;
        address indexToken;
        uint256 amountOut;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        uint256 acceptablePrice;
        uint256 minOut;
        uint256 executionFee;
    }

    mapping (uint256 => IncreasePositionRequest) public increasePositionRequests;
    mapping (uint256 => DecreasePositionRequest) public decreasePositionRequests;

    mapping (address => uint256) public increasePositionCount;
    mapping (address => uint256) public decreasePositionCount;

    mapping (address => bool) public isBotKeeper;
    mapping (address => User) public users;

    mapping(address => mapping(address => uint256)) public pendingRevenue;

    address public adminAddress;
    address public tokenPlay;
    address public positionRouter;
    address public vault;
    address public router;

    uint256 public botExecutionFee; // USDC

    // Recover NFT tokens sent by accident
    event NonFungibleTokenRecovery(address indexed token, uint256 indexed tokenId);

    // Recover ERC20 tokens sent by accident
    event TokenRecovery(address indexed token, uint256 amount);

    event Deposit(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);

    // Pending revenue is claimed
    event RevenueClaim(address indexed claimer, uint256 amount);

    constructor(
        address _tokenPlay,
        address _positionRouter,
        address _vault,
        address _router
    ) {
        adminAddress = msg.sender;
        // console.log("adminAddress: ", adminAddress);
        // _increasePositionRequestKeys.add(0x3fa7fb4698d2f7eb41de9b189e6df608303618cc9fac2c046ab27a6e7690fe57);
        tokenPlay = _tokenPlay;

        positionRouter = _positionRouter;
        vault = _vault;
        router = _router;

        botExecutionFee = 100000; // 0.1 USDC
        isBotKeeper[msg.sender] = true;
    }

    // Modifier for execution roles
    modifier onlyBotKeeper() {
        require(isBotKeeper[_msgSender()] == true, "Not is bot Keeper");
        _;
    }

    function setBotKeeper(address _account, bool _status) external {
        require(msg.sender == adminAddress, "Not admin");
        isBotKeeper[_account] = _status;
    }

    function setApprovePlugin(address _plugin) external {
        require(msg.sender == adminAddress, "Not admin");

        IRouter(router).approvePlugin(_plugin);
    }

    function depositUsdc(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Deposit: requie amount > 0");
        IERC20(tokenPlay).safeTransferFrom(address(msg.sender), address(this), _amount);
        User storage user = users[msg.sender];

        user.account = msg.sender;
        user.balance += _amount;
        user.depositBalance += _amount;
        emit Deposit(msg.sender, _amount);
    }

    function withdrawBalance(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Withdraw: requie amount > 0");
        User storage user = users[msg.sender];
        require(_amount <= user.balance, "Withdraw: requie amount > 0");
        IERC20(tokenPlay).safeTransferFrom(address(this), address(msg.sender), _amount);
        user.balance -= _amount;
        emit Withdraw(msg.sender, _amount);
    }

    function createIncreasePosition(
        address _user,
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode
    ) external payable nonReentrant onlyBotKeeper returns (bytes32) {
        require(msg.value == _executionFee, "val");
        require(_path.length == 1 || _path.length == 2, "len");
        require(_path[0] == tokenPlay, "Wrong token play");

        User storage user = users[_user];
        require(_amountIn <= user.balance - botExecutionFee, "CreateIncreasePosition: require _amountIn < user.balance");
        require(user.balance > 0, "CreateIncreasePosition: require user.balance > 0");

        IERC20(tokenPlay).safeTransfer(positionRouter, _amountIn);

        bytes32 key = IPositionRouter(positionRouter).createIncreasePosition{value: msg.value}(
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            _referralCode,
            0x0000000000000000000000000000000000000000
        );

        user.balance -= _amountIn;
        user.balance -= botExecutionFee;
        user.marginBalance += _amountIn;
        pendingRevenue[adminAddress][tokenPlay] += botExecutionFee;

        increasePositionCount[_user] += 1;
        uint256 count = increasePositionCount[_user];

        increasePositionRequests[count] = IncreasePositionRequest({
            account: _user,
            requestKey: key,
            botFee: botExecutionFee,
            path: _path,
            indexToken: _indexToken,
            amountIn: _amountIn,
            minOut: _minOut,
            sizeDelta: _sizeDelta,
            isLong: _isLong,
            acceptablePrice: _acceptablePrice,
            executionFee: _executionFee
        });

        return key;
    }

    function createDecreasePosition(
        address _user,
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _minOut
    ) external nonReentrant onlyBotKeeper returns (bool) {
        require(_path.length == 1 || _path.length == 2, "len");
        require(_path[1] == tokenPlay, "Wrong token play");
        if (_user == address(0)) { return true; }
        
        uint256 amountOut = _decreasePosition(address(this), _path[0], _indexToken, _collateralDelta, _sizeDelta, _isLong, address(this), _acceptablePrice);

        if (_path.length > 1) {
            IERC20(_path[0]).safeTransfer(vault, amountOut);
            amountOut = _vaultSwap(_path[0], _path[1], _minOut, address(this));
        }

        User storage user = users[_user];
        user.balance -= amountOut;
        user.balance -= botExecutionFee;
        pendingRevenue[adminAddress][tokenPlay] += botExecutionFee;

        decreasePositionCount[_user] += 1;
        uint256 count = decreasePositionCount[_user];
        
        decreasePositionRequests[count] = DecreasePositionRequest({
            account: _user,
            botFee: botExecutionFee,
            path: _path,
            indexToken: _indexToken,
            amountOut: amountOut,
            collateralDelta: _collateralDelta,
            sizeDelta: _sizeDelta,
            isLong: _isLong,
            acceptablePrice: _acceptablePrice,
            minOut: _minOut,
            executionFee: 0
        });

        return true;
    }

    function _vaultSwap(address _tokenIn, address _tokenOut, uint256 _minOut, address _receiver) internal returns (uint256) {
        uint256 amountOut = IVault(vault).swap(_tokenIn, _tokenOut, _receiver);
        require(amountOut >= _minOut, "BasePositionManager: insufficient amountOut");
        return amountOut;
    }

    function _decreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver, uint256 _price) internal returns (uint256) {
        if (_isLong) {
            require(IVault(vault).getMinPrice(_indexToken) >= _price, "BasePositionManager: mark price lower than limit");
        } else {
            require(IVault(vault).getMaxPrice(_indexToken) <= _price, "BasePositionManager: mark price higher than limit");
        }

        uint256 amountOut = IVault(vault).decreasePosition(_account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, _receiver);

        return amountOut;
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
}
