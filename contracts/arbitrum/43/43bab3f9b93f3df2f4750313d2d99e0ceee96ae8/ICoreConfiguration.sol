// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC20Stable.sol";
import "./IPositionToken.sol";
import "./IFoxifyAffiliation.sol";
import "./IFoxifyReferral.sol";
import "./IFoxifyBlacklist.sol";
import "./ISwapperConnector.sol";
import "./ICoreUtilities.sol";

interface ICoreConfiguration {
    struct FeeConfiguration {
        address feeRecipient;
        uint256 autoResolveFee;
        uint256 protocolFee;
        uint256 flashloanFee;
    }

    struct ImmutableConfiguration {
        IFoxifyBlacklist blacklist;
        IFoxifyReferral referral;
        IFoxifyAffiliation affiliation;
        IPositionToken positionTokenAccepter;
        IERC20Stable stable;
        ICoreUtilities utils;
    }

    struct LimitsConfiguration {
        uint256 minKeeperFee;
        uint256 minOrderRate;
        uint256 maxOrderRate;
        uint256 minDuration;
        uint256 maxDuration;
        uint256 maxAutoResolveDuration;
    }

    struct NFTDiscountLevel {
        uint256 bronze;
        uint256 silver;
        uint256 gold;
    }

    struct Swapper {
        ISwapperConnector swapperConnector;
        bytes path;
    }

    function discount() external view returns (uint256 bronze, uint256 silver, uint256 gold);

    function feeConfiguration()
        external
        view
        returns (address feeRecipient, uint256 autoResolveFee, uint256 protocolFee, uint256 flashloanFee);

    function immutableConfiguration()
        external
        view
        returns (
            IFoxifyBlacklist blacklist,
            IFoxifyReferral referral,
            IFoxifyAffiliation affiliation,
            IPositionToken positionTokenAccepter,
            IERC20Stable stable,
            ICoreUtilities utils
        );

    function keepers(uint256 index) external view returns (address);

    function keepersCount() external view returns (uint256);

    function keepersContains(address keeper) external view returns (bool);

    function limitsConfiguration()
        external
        view
        returns (
            uint256 minKeeperFee,
            uint256 minOrderRate,
            uint256 maxOrderRate,
            uint256 minDuration,
            uint256 maxDuration,
            uint256 maxAutoResolveDuration
        );

    function oracles(uint256 index) external view returns (address);

    function oraclesCount() external view returns (uint256);

    function oraclesContains(address oracle) external view returns (bool);

    function oraclesWhitelist(uint256 index) external view returns (address);

    function oraclesWhitelistCount() external view returns (uint256);

    function oraclesWhitelistContains(address oracle) external view returns (bool);

    function swapper() external view returns (ISwapperConnector swapperConnector, bytes memory path);

    event DiscountUpdated(NFTDiscountLevel discount_);
    event FeeConfigurationUpdated(FeeConfiguration config);
    event KeepersAdded(address[] keepers);
    event KeepersRemoved(address[] keepers);
    event LimitsConfigurationUpdated(LimitsConfiguration config);
    event OraclesAdded(address[] oracles);
    event OraclesRemoved(address[] oracles);
    event OraclesWhitelistRemoved(address[] oracles);
    event SwapperUpdated(Swapper swapper);
}

