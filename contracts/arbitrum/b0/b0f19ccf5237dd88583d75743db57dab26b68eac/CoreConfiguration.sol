// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./EnumerableSet.sol";
import "./Ownable.sol";
import "./ICoreConfiguration.sol";

contract CoreConfiguration is ICoreConfiguration, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant DIVIDER = 1 ether;
    uint256 public constant MAX_PROTOCOL_FEE = 0.2 ether; // TODO: need set production value
    uint256 public constant MAX_FLASHLOAN_FEE = 0.2 ether; // TODO: need set production value

    NFTDiscountLevel private _discount;
    FeeConfiguration private _feeConfiguration;
    ImmutableConfiguration private _immutableConfiguration;
    LimitsConfiguration private _limitsConfiguration;
    Swapper private _swapper;

    EnumerableSet.AddressSet private _keepers;
    EnumerableSet.AddressSet private _oracles;
    EnumerableSet.AddressSet private _oraclesWhitelist;

    function discount() external view returns (uint256 bronze, uint256 silver, uint256 gold) {
        return (_discount.bronze, _discount.silver, _discount.gold);
    }

    function feeConfiguration() external view returns (
        address feeRecipient,
        uint256 autoResolveFee,
        uint256 protocolFee,
        uint256 flashloanFee
    ) {
        return (
            _feeConfiguration.feeRecipient,
            _feeConfiguration.autoResolveFee,
            _feeConfiguration.protocolFee,
            _feeConfiguration.flashloanFee
        );
    }

    function immutableConfiguration() external view returns (
        IFoxifyBlacklist blacklist,
        IFoxifyAffiliation affiliation,
        IPositionToken positionTokenAccepter,
        IERC20Stable stable
    ) {
        return (
            _immutableConfiguration.blacklist,
            _immutableConfiguration.affiliation,
            _immutableConfiguration.positionTokenAccepter,
            _immutableConfiguration.stable
        );
    }

    function keepers(uint256 index) external view returns (address) {
        return _keepers.at(index);
    }

    function keepersCount() external view returns (uint256) {
        return _keepers.length();
    }

    function keepersContains(address keeper) external view returns (bool) {
        return _keepers.contains(keeper);
    }

    function limitsConfiguration() external view returns (
        uint256 minStableAmount,
        uint256 minOrderRate,
        uint256 maxOrderRate,
        uint256 minDuration,
        uint256 maxDuration
    ) {
        return (
            _limitsConfiguration.minStableAmount,
            _limitsConfiguration.minOrderRate,
            _limitsConfiguration.maxOrderRate,
            _limitsConfiguration.minDuration,
            _limitsConfiguration.maxDuration
        );
    }

    function oracles(uint256 index) external view returns (address) {
        return _oracles.at(index);
    }

    function oraclesCount() external view returns (uint256) {
        return _oracles.length();
    }

    function oraclesContains(address oracle) external view returns (bool) {
        return _oracles.contains(oracle);
    }

    function oraclesWhitelist(uint256 index) external view returns (address) {
        return _oraclesWhitelist.at(index);
    }

    function oraclesWhitelistCount() external view returns (uint256) {
        return _oraclesWhitelist.length();
    }

    function oraclesWhitelistContains(address oracle) external view returns (bool) {
        return _oraclesWhitelist.contains(oracle);
    }


    function swapper() external view returns (ISwapperConnector connector, bytes memory path) {
        return (_swapper.swapperConnector, _swapper.path);
    }

    constructor(
        ImmutableConfiguration memory immutableConfiguration_,
        NFTDiscountLevel memory discount_,
        FeeConfiguration memory feeConfiguration_,
        LimitsConfiguration memory limitsConfiguration_,
        Swapper memory swapper_
    ) {
        require(address(immutableConfiguration_.stable) != address(0), "CoreConfiguration: Stable is zero address");
        require(
            address(immutableConfiguration_.positionTokenAccepter) != address(0),
            "CoreConfiguration: Position token Accepter is zero address"
        );
        require(
            address(immutableConfiguration_.affiliation) != address(0),
            "CoreConfiguration: Affiliation is zero address"
        );
        require(
            address(immutableConfiguration_.blacklist) != address(0),
            "CoreConfiguration: Blacklist is zero address"
        );
        _immutableConfiguration = immutableConfiguration_;
        _updateDiscount(discount_);
        _updateFeeConfiguration(feeConfiguration_);
        _updateLimitsConfiguration(limitsConfiguration_);
        _updateSwapper(swapper_);
    }

    function addKeepers(address[] memory keepers_) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < keepers_.length; i++) {
            address keeper_ = keepers_[i];
            require(keeper_ != address(0), "CoreConfiguration: Keeper is zero address");
            _keepers.add(keeper_);
        }
        emit KeepersAdded(keepers_);
        return true;
    }

    function addOracles(address[] memory oracles_) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < oracles_.length; i++) {
            _oracles.add(oracles_[i]);
            _oraclesWhitelist.add(oracles_[i]);
        }
        emit OraclesAdded(oracles_);
        return true;
    }

    function removeKeepers(address[] memory keepers_) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < keepers_.length; i++) {
            address keeper_ = keepers_[i];
            _keepers.remove(keeper_);
        }
        emit KeepersRemoved(keepers_);
        return true;
    }

    function removeOracles(address[] memory oracles_) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < oracles_.length; i++) {
            _oracles.remove(oracles_[i]);
        }
        emit OraclesRemoved(oracles_);
        return true;
    }

    function removeOraclesWhitelist(address[] memory oracles_) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < oracles_.length; i++) {
            _oraclesWhitelist.remove(oracles_[i]);
        }
        emit OraclesWhitelistRemoved(oracles_);
        return true;
    }

    function updateDiscount(NFTDiscountLevel memory discount_) external onlyOwner returns (bool) {
        _updateDiscount(discount_);
        return true;
    }

    function updateFeeConfiguration(FeeConfiguration memory config) external onlyOwner returns (bool) {
        _updateFeeConfiguration(config);
        return true;
    }

    function updateLimitsConfiguration(LimitsConfiguration memory config) external onlyOwner returns (bool) {
        _updateLimitsConfiguration(config);
        return true;
    }

    function updateSwapper(Swapper memory swapper_) external onlyOwner returns (bool) {
        _updateSwapper(swapper_);
        return true;
    }

    function _updateDiscount(NFTDiscountLevel memory discount_) private {
        require(
            discount_.bronze <= DIVIDER && discount_.silver <= DIVIDER && discount_.gold <= DIVIDER,
            "CoreConfiguration: Invalid discount value"
        );
        _discount = discount_;
        emit DiscountUpdated(discount_);
    }

    function _updateFeeConfiguration(FeeConfiguration memory config) private {
        require(config.feeRecipient != address(0), "CoreConfiguration: Recipient is zero address");
        require(config.protocolFee <= MAX_PROTOCOL_FEE, "CoreConfiguration: Protocol fee gt max");
        require(config.flashloanFee <= MAX_FLASHLOAN_FEE, "CoreConfiguration: Flashloan fee gt max");
        _feeConfiguration = config;
        emit FeeConfigurationUpdated(config);
    }

    function _updateLimitsConfiguration(LimitsConfiguration memory config) private {
        require(config.minStableAmount > 0, "CoreConfiguration: Min stable is not positive");
        require(config.minOrderRate > 0, "CoreConfiguration: Min rate is not positive");
        require(config.maxOrderRate >= config.minOrderRate, "CoreConfiguration: Max order rate lt min");
        require(config.maxDuration >= config.minDuration, "CoreConfiguration: Max duration lt min");
        _limitsConfiguration = config;
        emit LimitsConfigurationUpdated(config);
    }

    function _updateSwapper(Swapper memory swapper_) private {
        require(address(swapper_.swapperConnector) != address(0), "CoreConfiguration: Connector is zero address");
        require(swapper_.path.length > 0, "CoreConfiguration: Path is zero address");
        _swapper = swapper_;
        emit SwapperUpdated(swapper_);
    }
}

