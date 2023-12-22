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
    address public constant triggerServer = address(0x0Ce305012CEAf04E7D94E1e276B86C2d5E046b98);
    // @address:FEEDER
    IFeeder public constant feeder = IFeeder(0x5480618e8a8042854f6cD322Cd9d8a9a848D2360);
    // @address:INTERACTION
    IInteraction public constant interaction = IInteraction(0x1AA9809d6B45897C52f4aD82E8F00c64ED9c6211);
    // @address:FEES
    IFees public constant fees = IFees(0x18b6613a2b61ca4adD5041cD673E00B4BE322026);
    // @address:TRADE_BEACON
    address public constant tradeBeacon = address(0x3A04b2327Cea7cDeb81E89195e53d6e63b5f9B95);
    // @address:DRIP_OPERATOR
    IDripOperator public constant dripOperator = IDripOperator(0xC40110E5d03b7e512b8C3Ebeb74e532b5E1D22eC);
    // @address:ETH_PRICE_FEED
    IPriceFeed public constant ethPriceFeed = IPriceFeed(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
    // @address:WHITELIST
    IWhitelist public constant whitelist = IWhitelist(0x2872265760368BD508a3aED70d1F32fac487B78a);
    // @address:TRADE_PARAMS_UPDATER
    ITradeParamsUpdater public constant tradeParamsUpdater = ITradeParamsUpdater(0xb9BE208fFc4D7d173a584e8a0bC66c3c37A90Be6);
    // @address:UPGRADER
    IUpgrader public constant upgrader = IUpgrader(0xBD796409f3b0ec376f4eFc3476A90d4777CDDffA);
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
    IFundFactory public constant fundFactory = IFundFactory(0xa8c4a785Ce7B2eE85a939ff65Ebe0Cb2a74482CD);
}

