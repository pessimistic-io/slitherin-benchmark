// SPDX-License-Identifier: ISC

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Upgradeable.sol";
import "./IRegistry.sol";

contract Registry is IRegistry, Upgradeable {
    function initialize() public initializer {
        __Ownable_init();
    }
    // @address:USDT
    IERC20MetadataUpgradeable public constant usdt = IERC20MetadataUpgradeable(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    // @address:TRIGGER_SERVER
    address public constant triggerServer = address(0x97Cd3064aBE3BB089D37e5613Ec53Bc8Bf622728);
    // @address:FEEDER
    IFeeder public constant feeder = IFeeder(0xF989582F22592df2DEFAf9D38522Ef25C29e6A8e);
    // @address:INTERACTION
    IInteraction public constant interaction = IInteraction(0x8A1D20808dD657864840F7e089f3FCC0230a4550);
    // @address:FEES
    IFees public constant fees = IFees(0xBed75bEE9FfA4Ec80ef33b4A0beb258da3c80269);
    // @address:TRADE_BEACON
    address public constant tradeBeacon = address(0x7fd774f1528818e736E34aec3D38a3f46e51D67e);
    // @address:DRIP_OPERATOR
    IDripOperator public constant dripOperator = IDripOperator(0xD1E0F43DF50aB236991591f3257b723974bd7960);
    // @address:ETH_PRICE_FEED
    IPriceFeed public constant ethPriceFeed = IPriceFeed(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
    // @address:WHITELIST
    IWhitelist public constant whitelist = IWhitelist(0xC6c7ED9E47e30579A801d25cC53c99cE3E94d53d);
    // @address:TRADE_PARAMS_UPDATER
    ITradeParamsUpdater public constant tradeParamsUpdater = ITradeParamsUpdater(0xe9Ab2b6307EAdBBDcB0Bea875bd4bBE44484f79A);
    // @address:UPGRADER
    IUpgrader public constant upgrader = IUpgrader(0x8A9515FEAd803967402e5cf0c45883959C9b40dB);
    // @address:SWAPPER
    address public constant swapper = address(0xDef1C0ded9bec7F1a1670819833240f027b25EfF);
    // @address:AAVE_POOL_DATA_PROVIDER
    IPoolDataProvider public constant aavePoolDataProvider = IPoolDataProvider(0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654);
    // @address:AAVE_POOL
    IPool public constant aavePool = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    // @address:GMX_ROUTER
    IGmxRouter public constant gmxRouter = IGmxRouter(0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064);
    // @address:GMX_POSITION_ROUTER
    IPositionRouter public constant gmxPositionRouter = IPositionRouter(0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868);
    // @address:FUND_FACTORY
    IFundFactory public constant fundFactory = IFundFactory(0x734e415cD8a08E442404D8A3E36597C1be4D9e69);
}

