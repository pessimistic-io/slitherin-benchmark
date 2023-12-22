// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IMasterChef.sol";
import "./ITokenBurnable.sol";
import "./IAggregatorV3Interface.sol";

import "./console.sol";

interface IWater {
    function lend(uint256 _amount, address _receiver) external returns (bool);

    function repayDebt(uint256 leverage, uint256 debtValue) external;

    function getTotalDebt() external view returns (uint256);

    function updateTotalDebt(uint256 profit) external returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function balanceOfUSDC() external view returns (uint256);

    function asset() external view returns (address);
}

interface IVodkaV2 {

    struct GMXPoolAddresses {
        address longToken;
        address shortToken;
        address marketToken;
        address indexToken;
        address longTokenVault;
        address shortTokenVault;
    }

    function gmxPoolAddresses(
        address longToken
    ) external view returns (GMXPoolAddresses memory);
}

contract WaterLendingHandler is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;
    using MathUpgradeable for uint128;

    struct Vaults {
        IWater vaultAAddress;
        IWater vaultBAddress;
        address vaultATokenAsset;
        address vaultBTokenAsset;
        IAggregatorV3Interface priceFeed;
    }

    address public vodkaVault;
    uint256 public MAX_BPS;
    uint256 public MAX_LEVERAGE;

    mapping(address => address) public longTokenToFeed;

    // asset ratio will be assumed to be declared here
    uint256 public ratio;

    event SetVaultsAddresses(address token, address feed);
    event Setkeepr(address keeper);
    event SetVodka(address vodkaVault);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        MAX_BPS = 100_000;
        ratio = 50_000;
        MAX_LEVERAGE = 10_000;

        __Ownable_init();
        __ReentrancyGuard_init();
    }

    modifier onlyVodkavault() {
        require(msg.sender == vodkaVault, "Not allowed to borrow");
        _;
    }

    modifier zeroAddress(address addr) {
        require(addr != address(0), "Zero address");
        _;
    }

    function setFeedAddress(
        address _longToken,
        address _longTokenFeed
    ) external onlyOwner {
        require(_longToken != address(0), "Zero address");
        require(_longTokenFeed != address(0), "Zero address");
        longTokenToFeed[_longToken] = _longTokenFeed;
        emit SetVaultsAddresses(_longToken, _longTokenFeed);
    }

    function setVodkaVault(address _vodkaVault) external onlyOwner {
        vodkaVault = _vodkaVault;
        emit SetVodka(_vodkaVault);
    }

    function getLatestData(address _longToken) public view returns (uint256) {
        address _priceFeed = longTokenToFeed[_longToken];
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) =  IAggregatorV3Interface(_priceFeed).latestRoundData(); //in 1e8
        // convert answer to 1e18
        uint8 _decimals = IAggregatorV3Interface(_priceFeed).decimals();

        return uint256(answer) * 1e10;
    }

    function borrow(
        uint256 amountIn,
        uint256 leverageSize,
        address _longToken,
        address _shortToken
    ) external onlyVodkavault returns (uint256 assetABorrowAmount, uint256 assetBBorrowAmount) {
        console.log("amountIn", amountIn);
        require(amountIn > 0, "Amount must be greater than 0");
        console.log("before gmp");
        IVodkaV2.GMXPoolAddresses memory gmp = IVodkaV2(msg.sender).gmxPoolAddresses(_longToken);
        console.log("_longToken", _longToken);
        console.log("gmp.longToken", gmp.longToken);
        console.log("gmp.shortToken", gmp.shortToken);
        console.log("gmp.marketToken", gmp.marketToken);
        console.log("gmp.indexToken", gmp.indexToken);
        console.log("gmp.longTokenVault", gmp.longTokenVault);
        console.log("gmp.shortTokenVault", gmp.shortTokenVault);
        // ............................
        uint256 initAmount = amountIn.mulDiv(leverageSize, 1_000);
        assetABorrowAmount = (initAmount * ratio / MAX_BPS ) - amountIn;
        uint256 usdcToEthBorrowAmount = (initAmount * ratio / MAX_BPS );
        console.log("usdcToEthBorrowAmount", usdcToEthBorrowAmount); // 10000000000
        // // IAggregatorV3Interface _priceFeed = vault.priceFeed;
        console.log("getLatestData(gmp.longToken)", getLatestData(gmp.longToken));
        // 163304239999 999998693566080000
        // 1633 042400000000000000
        // 1500000000000000000
        // 309322258969569111
        // // usdc is 6 decimals
        // // @todo subject to check
        assetBBorrowAmount = ((usdcToEthBorrowAmount * 1e12) * 1e18) / getLatestData(gmp.longToken);
        // ...........................

        console.log("passed gmp");
        // uint256 initAmount = amountIn.mulDiv(leverageSize, 1_000) - amountIn;
        console.log("initAmount", initAmount); // 200000
        // uint256 poolProportion = (initAmount + amountIn) * 50 / 100;
        // console.log("poolProportion", poolProportion); // 100000
        // assetBBorrowAmount = poolProportion - amountIn;
        console.log("assetBBorrowAmount", assetBBorrowAmount); 
        // 946910344574197
        // 1100000000000000

        // assetABorrowAmount = ((poolProportion * 1e12) * 1e18) / getLatestData(gmp.longToken) * 1e8;
        console.log("assetABorrowAmount", assetABorrowAmount); // 9999900000

        console.log("gmp.longTokenVault", gmp.longTokenVault);
        // 0xBA53667889491897B76b8a07269D979e8BbF8e6F
        // 61474700 000000
        // bool ethBorrowed = IWater(gmp.longTokenVault).lend(assetABorrowAmount, msg.sender);
        bool ethBorrowed = IWater(gmp.longTokenVault).lend(1000000, msg.sender);
        // 308949547933281381
        console.log("ethBorrowed", ethBorrowed);
        // bool usdcBorrowed = IWater(gmp.shortTokenVault).lend(assetBBorrowAmount, msg.sender);
        bool usdcBorrowed = IWater(gmp.shortTokenVault).lend(1000, msg.sender);
        console.log("usdcBorrowed", usdcBorrowed);
        // require both borrow to be successful
        require(ethBorrowed && usdcBorrowed, "Borrow failed");
        return (assetABorrowAmount, assetBBorrowAmount + amountIn);
    }
}

