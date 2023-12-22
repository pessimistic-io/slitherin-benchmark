// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./MathUpgradeable.sol";

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

    function balanceOfAsset() external view returns (uint256);

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

    function gmxPoolAddresses(address longToken) external view returns (GMXPoolAddresses memory);
}

contract WaterLendingHandler is OwnableUpgradeable, PausableUpgradeable {
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
    uint256 public DECIMAL;
    uint256 public MAX_LEVERAGE;

    mapping(address => address) public longTokenToFeed;

    // asset ratio will be assumed to be declared here
    uint256 public ratio;
    address USDC;
    address WBTC;

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
        DECIMAL = 1e18;
        MAX_LEVERAGE = 10_000;

        __Ownable_init();
    }

    modifier onlyVodkavault() {
        require(msg.sender == vodkaVault, "Not allowed to borrow");
        _;
    }

    modifier zeroAddress(address addr) {
        require(addr != address(0), "Zero address");
        _;
    }

    function setWBTC(address _WBTC) external onlyOwner {
        WBTC = _WBTC;
    }

    function setUSDC(address _USDC) external onlyOwner {
        USDC = _USDC;
    }

    function setFeedAddress(address _longToken, address _longTokenFeed) external onlyOwner {
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
        (, /* uint80 roundID */ int answer /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/, , , ) = IAggregatorV3Interface(
            _priceFeed
        ).latestRoundData(); //in 1e8
        return uint256(answer) * 1e10;
    }

    function previewBorrowedAmounts(
        uint256 _amountIn,
        uint256 _leverageSize,
        address _longToken
    ) public view returns (uint256 longTokenOutputAmount, uint256 shortTokenAmountAmount) {
        if (_amountIn == 0  || _leverageSize == 0) {
            return (0, 0);
        }
        // Get GMX pool addresses
        IVodkaV2.GMXPoolAddresses memory gmp = IVodkaV2(vodkaVault).gmxPoolAddresses(_longToken);

        // Calculate initial borrow amount based on leverage ratio and amount in
        uint256 initAmount = _amountIn.mulDiv(_leverageSize, 1_000) - _amountIn;
        // Allocate 50% of total to each asset
        uint256 poolProportion = ((initAmount + _amountIn) * 50) / 100;
        // Asset B borrow amount is pool proportion less deposit amount
        shortTokenAmountAmount = poolProportion - _amountIn;
        console.log("CA: getLatestData(gmp.longToken)", getLatestData(gmp.longToken));

        if (_longToken == USDC) {
            console.log("CA: in usdc");
            // since price of long token which is USDC is in pow of 18
            // we need to convert it to pow of 6
            longTokenOutputAmount = (poolProportion * 1e18) / getLatestData(gmp.longToken);
        } else if(_longToken == WBTC) {
            console.log("CA: in wbtc");
            // since price of long token which is WBTC is converted to pow of 18
            // and wbt decimal is 8, why usdc decimal is 6
            // we need to convert it to pow of 8 by mul by 1e20
            longTokenOutputAmount = ((poolProportion * 1e20) / getLatestData(gmp.longToken));
        } else {
            console.log("CA: in else");
            // other assets like weth, arb are consider to be in pow of 18
            longTokenOutputAmount = (((poolProportion * 1e12) * 1e18) / getLatestData(gmp.longToken));
        }
    }

    function borrow(
        uint256 _amountIn,
        uint256 _leverageSize,
        address _longToken
    ) external onlyVodkavault returns (uint256 longTokenOutputAmount, uint256 shortTokenAmountAmount) {
        require(_amountIn > 0, "Amount must be greater than 0");
        console.log("before gmp");
        // Get GMX pool addresses
        IVodkaV2.GMXPoolAddresses memory gmp = IVodkaV2(msg.sender).gmxPoolAddresses(_longToken);

        (longTokenOutputAmount, shortTokenAmountAmount) = previewBorrowedAmounts(_amountIn, _leverageSize, _longToken);
        console.log("CA: longTokenOutputAmount", longTokenOutputAmount); // 50000000 00 00000000
        console.log("CA: shortTokenAmountAmount", shortTokenAmountAmount);
        console.log("CA: gmp.longTokenVault", gmp.longTokenVault);
        console.log("CA: gmp.shortTokenVault", gmp.shortTokenVault);
        // Borrow Asset A from long token vault
        bool ethBorrowed = IWater(gmp.longTokenVault).lend(longTokenOutputAmount, msg.sender);
        console.log("ethBorrowed", ethBorrowed);
        // Borrow Asset B from short token vault
        bool usdcBorrowed = IWater(gmp.shortTokenVault).lend(shortTokenAmountAmount, msg.sender);
        console.log("ethBorrowed", ethBorrowed);
        // require both borrow to be successful
        require(ethBorrowed && usdcBorrowed, "Borrow failed");
        return (longTokenOutputAmount, shortTokenAmountAmount);
    }
}

