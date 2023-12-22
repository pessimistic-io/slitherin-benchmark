// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./Userable.sol";
import "./Boreable.sol";
import "./IUserNFTDescriptor.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./CountersUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./TransferHelper.sol";
import "./ISwapRouter.sol";


abstract contract BaseUserManager is
    Userable,
    Initializable,
    OwnableUpgradeable,
    ERC721EnumerableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    CountersUpgradeable.Counter public userCounter;

    mapping(AprType => BaseApr) public aprs;
    mapping(uint256 => User) public users;
    mapping(uint256 => UserGame) public usersGame;
    mapping(AprType => address) public nftDescriptor;

    uint24 public creationFee;
    uint24 public rewardFee;
    address public teamWallet;
    uint256 public minimumSellThreshold;
    address public router;
    address public weth;
    uint24 public poolFee;

    address public boredInBorderland;

    uint256 public penality;

    modifier onlyUserOwner(uint256 tokenId) {
        require(tokenId != 0 && _exists(tokenId), "This token does not exist");
        require(_ownerOf(tokenId) == _msgSender(), "You are not the owner");
        _;
    }

    modifier onlyExist(uint256 tokenId) {
        require(tokenId != 0 && _exists(tokenId), "This token does not exist");
        _;
    }

    modifier canCreate(AprType category, uint256 value) {
        require(_msgSender() != address(0), "Cannot be zero address");
        require(_isExistAprType(category), "The category not exist");
        require(
            boredInBorderland != address(0),
            "ERC20: Missing implementation"
        );
        require(
            aprs[category].priceMin <= value &&
                value <= aprs[category].priceMax,
            "Value outside threshold"
        );
        require(
            IERC20Upgradeable(boredInBorderland).balanceOf(_msgSender()) >=
                value,
            "Insufficient funds"
        );
        require(
            IERC20Upgradeable(boredInBorderland).allowance(
                _msgSender(),
                address(this)
            ) >= value,
            "Insufficient allowance"
        );
        _;
    }

    function initialize() public initializer {
        __ERC721_init("Bored In Borderland", "BIB");
        __ERC721Enumerable_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        aprs[AprType.BORED] = BaseApr({
            apr: 72000000,
            priceMin: 250 ether,
            priceMax: 250 ether
        });
        aprs[AprType.MUTANT] = BaseApr({
            apr: 51000000,
            priceMin: 50 ether,
            priceMax: 50 ether
        });
        aprs[AprType.SOUL] = BaseApr({
            apr: 30000000,
            priceMin: 1 ether,
            priceMax: 10 ether
        });
        creationFee = 10;
        rewardFee = 5;
        minimumSellThreshold = 840 ether;
        router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        poolFee = 10000;
        penality = 3000000;
        _init();
    }

    function createUser(
        uint256 _value,
        AprType _category,
        string memory _name
    )
        public
        nonReentrant
        whenNotPaused
        canCreate(_category, _value)
        returns (uint256 tokenId)
    {
        uint256 teamIncentive = _computeFeeAmount(_value, creationFee);
        Boreable(boredInBorderland).userBurn(_msgSender(), _value - teamIncentive);
        IERC20Upgradeable(boredInBorderland).safeTransferFrom(
            _msgSender(),
            address(this),
            teamIncentive
        );
        _teamPayment();
        userCounter.increment();
        tokenId = userCounter.current();
        users[tokenId] = User({
            balance: _value,
            initialBalance: _value,
            category: _category,
            name: _name,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });
        _safeMint(_msgSender(), tokenId);
        emit Created(
            _msgSender(),
            tokenId,
            _category,
            _value,
            block.timestamp
        );
    }

    function getUserDescription(
        uint256 tokenId
    ) public view override returns (UserDescription memory) {
        return
            UserDescription({
                userId: tokenId,
                balance: users[tokenId].balance,
                apr: getLatestAprOf(tokenId),
                category: users[tokenId].category,
                initialBalance: users[tokenId].initialBalance,
                name: users[tokenId].name
            });
    }

    function getLatestAprOf(
        uint256 tokenId
    ) public view virtual returns (uint256);

    function setRouter(address newRouter) external onlyOwner {
        router = newRouter;
    }

    function setPoolFee(uint24 _poolFee) external onlyOwner {
        poolFee = _poolFee;
    }

    function setTeamWallet(address account) external onlyOwner {
        teamWallet = account;
    }

    function setMinimumSellThreshold(uint256 threshold) external onlyOwner {
        minimumSellThreshold = threshold;
    }

    function setWETH(address _weth) external onlyOwner {
        weth = _weth;
    }

    function setToken(address token) external onlyOwner {
        boredInBorderland = token;
    }

    function setFee(
        uint24 newCreationFee,
        uint24 newRewardFee
    ) external onlyOwner {
        creationFee = newCreationFee;
        rewardFee = newRewardFee;
    }

    function setDescriptor(
        AprType category,
        address descriptor
    ) public onlyOwner {
        nftDescriptor[category] = descriptor;
    }

    function setPenality(uint256 value) public onlyOwner {
        penality = value;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721Upgradeable)
        onlyExist(tokenId)
        returns (string memory)
    {
        return
            IUserNFTDescriptor(nftDescriptor[users[tokenId].category]).tokenURI(
                address(this),
                tokenId
            );
    }

    function setBaseApr(
        AprType category,
        BaseApr memory newBaseApr
    ) external virtual onlyOwner {
        require(_isExistAprType(category), "Category not exist");
        aprs[category].apr = newBaseApr.apr;
        aprs[category].priceMin = newBaseApr.priceMin;
        aprs[category].priceMax = newBaseApr.priceMax;
    }

    function _init() internal virtual {}

    function _isExistAprType(AprType aprType) internal pure returns (bool) {
        if (
            AprType.BORED == aprType ||
            AprType.MUTANT == aprType ||
            AprType.SOUL == aprType
        ) {
            return true;
        }
        return false;
    }

    function _computeFeeAmount(
        uint256 amount,
        uint256 feePercentage
    ) internal pure returns (uint256) {
        return (amount * feePercentage) / 100;
    }

    function _teamPayment() internal {
        uint256 balance = IERC20Upgradeable(boredInBorderland).balanceOf(
            address(this)
        );
        if (balance >= minimumSellThreshold) {
            uint256 sellAmount = balance / 2;
            uint256 transferAmount = balance - sellAmount;
            _sellTokens(sellAmount);
            IERC20Upgradeable(boredInBorderland).safeTransfer(
                teamWallet,
                transferAmount
            );
        }
    }

    function _sellTokens(uint256 _amount) internal {
        TransferHelper.safeApprove(boredInBorderland, router, _amount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: boredInBorderland,
                tokenOut: weth,
                fee: poolFee,
                recipient: teamWallet,
                deadline: block.timestamp + 300,
                amountIn: _amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        ISwapRouter(router).exactInputSingle(params);
    }
}

