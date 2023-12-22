// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import {IAToken} from "./IAToken.sol";
import {IAaveOracle} from "./IAaveOracle.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {IAaveProtocolDataProvider,TokenData} from "./IAaveProtocolDataProvider.sol";
import {IPool} from "./IPool.sol";

struct Info {
    address user;
    uint256 totalCollateralBase;
    uint256 totalDebtBase;
    uint256 availableBorrowsBase;
    uint256 currentLiquidationThreshold;
    uint256 ltv;
    uint256 healthFactor;
    Asset[] asset;
}

struct Asset {
    address addr;
    string name;
    string symbol;
    uint8 decimals;
    uint256 price;
    uint8 priceDecimals;
    uint256 balance;
    uint256 balanceBase;
    uint256 totalSupply;
    uint256 totalSupplyBase;
    Balance aBalance;
    Balance sBalance;
    Balance vBalance;
}

struct Balance {
    address addr;
    string name;
    string symbol;
    uint8 decimals;
    uint256 price;
    uint8 priceDecimals;
    uint256 balance;
    uint256 balanceBase;
    uint256 totalSupply;
    uint256 totalSupplyBase;
    string aka;
}

contract AaveAggregatorV3 is Initializable, OwnableUpgradeable {
    address public POOL_DATA_PROVIDER_PROXY_ADDRESS;
    address public POOL_ADDRESS;
    uint8 public PRICE_DECIMALS;

    function initialize() public initializer {
        __Ownable_init();
        POOL_DATA_PROVIDER_PROXY_ADDRESS = 0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654;
        POOL_ADDRESS = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
        PRICE_DECIMALS = 8;
    }

    function changePoolDataProviderProxyAddress(address newAddress) public onlyOwner {
        POOL_DATA_PROVIDER_PROXY_ADDRESS = newAddress;
    }

    function changePoolAddress(address newAddress) public onlyOwner {
        POOL_ADDRESS = newAddress;
    }

    function changePriceDecimals(uint8 newDecimals) public onlyOwner {
        PRICE_DECIMALS = newDecimals;
    }

    function getAssetLiability(address _user) public virtual view returns(Info memory info) {
        IAaveProtocolDataProvider poolDataProvider = IAaveProtocolDataProvider(POOL_DATA_PROVIDER_PROXY_ADDRESS);
        IPool pool = IPool(POOL_ADDRESS);
        TokenData[] memory tokens = poolDataProvider.getAllReservesTokens();

        info = Info(_user, 0, 0, 0, 0, 0, 0, new Asset[](tokens.length));

        for (uint256 i=0;i<tokens.length;i++) {
            info.asset[i] = _getAsset(tokens[i].tokenAddress, _user);
        }
        (info.totalCollateralBase, info.totalDebtBase, info.availableBorrowsBase, info.currentLiquidationThreshold, info.ltv, info.healthFactor) = pool.getUserAccountData(_user);
        return info;
    }

    function getAssetLiabilityOf(address _asset, address _user) public virtual view returns(Info memory info) {
        IPool pool = IPool(POOL_ADDRESS);

        info = Info(_user, 0, 0, 0, 0, 0, 0, new Asset[](1));
        info.asset[0] = _getAsset(_asset, _user);

        (info.totalCollateralBase, info.totalDebtBase, info.availableBorrowsBase, info.currentLiquidationThreshold, info.ltv, info.healthFactor) = pool.getUserAccountData(_user);
        return info;
    }

    function _getAsset(address _asset, address _user) internal view returns(Asset memory asset_) {
        IAaveProtocolDataProvider poolDataProvider = IAaveProtocolDataProvider(POOL_DATA_PROVIDER_PROXY_ADDRESS);
        IPool pool = IPool(POOL_ADDRESS);
        IPoolAddressesProvider poolAddressProvider = IPoolAddressesProvider(pool.ADDRESSES_PROVIDER());
        IAaveOracle oracle = IAaveOracle(poolAddressProvider.getPriceOracle());
        uint256 price = oracle.getAssetPrice(_asset);

        (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress) = poolDataProvider.getReserveTokensAddresses(_asset);
        Balance memory astBalance = _getBalance(_asset, price, _user);
        asset_ = Asset(_asset, astBalance.name, astBalance.symbol, astBalance.decimals, price, PRICE_DECIMALS, astBalance.balance, astBalance.balance*price/(10**PRICE_DECIMALS), astBalance.totalSupply, astBalance.totalSupply*price/(10**PRICE_DECIMALS), _getBalance(aTokenAddress, price, _user), _getBalance(stableDebtTokenAddress, price, _user), _getBalance(variableDebtTokenAddress, price, _user));
    }

    function _getBalance(address _tokenAddress, uint256 price, address _user) internal view returns(Balance memory balance_) {
        IERC20Metadata tokenMeta = IERC20Metadata(_tokenAddress);
        IERC20 token = IERC20(_tokenAddress);
        uint256 balance = token.balanceOf(_user);
        balance_ = Balance(_tokenAddress, tokenMeta.name(), tokenMeta.symbol(), tokenMeta.decimals(), price, PRICE_DECIMALS, balance, balance*price / (10**PRICE_DECIMALS), token.totalSupply(), token.totalSupply()*price/(10**PRICE_DECIMALS), tokenMeta.name());
    }
}
