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
    IFeeder public constant feeder = IFeeder(0xE76d78ce50B79a1570A66bC98fCD5C66eE0b8De6);
    // @address:INTERACTION
    IInteraction public constant interaction = IInteraction(0x9EFFB7e25079D4a33Bc1DBD569EcF6d2541f2f3e);
    // @address:FEES
    IFees public constant fees = IFees(0x12aaeB8De1C1d594cC5C713f471E9d9c5d3834A1);
    // @address:TRADE_BEACON
    address public constant tradeBeacon = address(0x9a0414BdD01c40aD828080a8809E8B0889904566);
    // @address:DRIP_OPERATOR
    IDripOperator public constant dripOperator = IDripOperator(0xC9D0681E6f8fB2c50CDE3465d455672A2d85a879);
    // @address:ETH_PRICE_FEED
    IPriceFeed public constant ethPriceFeed = IPriceFeed(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
    // @address:WHITELIST
    IWhitelist public constant whitelist = IWhitelist(0xcD7cd2934Ddc201215ea6e44d0B79911111f0e13);
    // @address:TRADE_PARAMS_UPDATER
    ITradeParamsUpdater public constant tradeParamsUpdater = ITradeParamsUpdater(0x31243e2A0F9dAEdDd538E9347cA791f87073d7a1);
    // @address:UPGRADER
    IUpgrader public constant upgrader = IUpgrader(0xd418B812322a98eaaEc3d379CBB7F3C0d28aa4Fd);
    // @address:SWAPPER
    address public constant swapper = address(0xDef1C0ded9bec7F1a1670819833240f027b25EfF);
    // @address:AAVE_POOL_DATA_PROVIDER
    address public constant aavePoolDataProvider = address(0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654);
    // @address:AAVE_POOL
    address public constant aavePool = address(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    // @address:GMX_ROUTER
    IGmxRouter public constant gmxRouter = IGmxRouter(0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064);
    // @address:GMX_POSITION_ROUTER
    IPositionRouter public constant gmxPositionRouter = IPositionRouter(0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868);
    // @address:FUND_FACTORY
    IFundFactory public constant fundFactory = IFundFactory(0x060cd0C7dc1251843a7A4515F4437b1De6ABb512);
}

