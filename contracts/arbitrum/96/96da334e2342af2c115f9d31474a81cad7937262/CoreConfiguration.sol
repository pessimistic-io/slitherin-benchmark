// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./EnumerableSet.sol";
import "./Ownable.sol";
import "./ICoreConfiguration.sol";

/**
 * @title CoreConfiguration
 * @notice This contract stores the core configuration of the Foxify protocol.
 */
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

    /**
     * @notice Returns the discount for NFTs of different tiers.
     * @return bronze The discount for bronze NFTs.
     * @return silver The discount for silver NFTs.
     * @return gold The discount for gold NFTs.
     */
    function discount() external view returns (uint256 bronze, uint256 silver, uint256 gold) {
        return (_discount.bronze, _discount.silver, _discount.gold);
    }

    /**
     * @notice Returns the fee configuration.
     * @return feeRecipient The address that receives the protocol fee.
     * @return autoResolveFee The fee for automatically resolving disputes.
     * @return protocolFee The fee for using the protocol.
     * @return flashloanFee The fee for taking out a flash loan.
     */
    function feeConfiguration()
        external
        view
        returns (address feeRecipient, uint256 autoResolveFee, uint256 protocolFee, uint256 flashloanFee)
    {
        return (
            _feeConfiguration.feeRecipient,
            _feeConfiguration.autoResolveFee,
            _feeConfiguration.protocolFee,
            _feeConfiguration.flashloanFee
        );
    }

    /**
     * @notice Returns the immutable configuration.
     * @return blacklist The address of the blacklist contract.
     * @return affiliation The address of the affiliation contract.
     * @return positionTokenAccepter The address of the position token accepter contract.
     * @return stable The address of the stablecoin contract.
     */
    function immutableConfiguration()
        external
        view
        returns (
            IFoxifyBlacklist blacklist,
            IFoxifyAffiliation affiliation,
            IPositionToken positionTokenAccepter,
            IERC20Stable stable,
            ICoreUtilities utils
        )
    {
        return (
            _immutableConfiguration.blacklist,
            _immutableConfiguration.affiliation,
            _immutableConfiguration.positionTokenAccepter,
            _immutableConfiguration.stable,
            _immutableConfiguration.utils
        );
    }

    /**
     * @notice Returns the list of keepers.
     * @param index The index of the keeper to return.
     * @return The address of the keeper at the specified index.
     */
    function keepers(uint256 index) external view returns (address) {
        return _keepers.at(index);
    }

    /**
     * @notice Returns the number of keepers.
     * @return The number of keepers.
     */
    function keepersCount() external view returns (uint256) {
        return _keepers.length();
    }

    /**
     * @notice Returns true if the specified address is a keeper.
     * @param keeper The address to check.
     * @return True if the specified address is a keeper. False otherwise.
     */
    function keepersContains(address keeper) external view returns (bool) {
        return _keepers.contains(keeper);
    }

    /**
     * @notice Get the limits configuration values.
     * @return minStableAmount The minimum stable amount allowed.
     * @return minOrderRate The minimum order rate allowed.
     * @return maxOrderRate The maximum order rate allowed.
     * @return minDuration The minimum duration allowed for an order.
     * @return maxDuration The maximum duration allowed for an order.
     */
    function limitsConfiguration()
        external
        view
        returns (
            uint256 minStableAmount,
            uint256 minOrderRate,
            uint256 maxOrderRate,
            uint256 minDuration,
            uint256 maxDuration
        )
    {
        return (
            _limitsConfiguration.minStableAmount,
            _limitsConfiguration.minOrderRate,
            _limitsConfiguration.maxOrderRate,
            _limitsConfiguration.minDuration,
            _limitsConfiguration.maxDuration
        );
    }

    /**
     * @notice Get the oracle at the specified index.
     * @param index The index of the oracle.
     * @return The address of the oracle.
     */
    function oracles(uint256 index) external view returns (address) {
        return _oracles.at(index);
    }

    /**
     * @notice Get the number of oracles.
     * @return The number of oracles.
     */
    function oraclesCount() external view returns (uint256) {
        return _oracles.length();
    }

    /**
     * @notice Check if the oracle exists in the oracles set.
     * @param oracle The address of the oracle.
     * @return A boolean indicating if the oracle exists.
     */
    function oraclesContains(address oracle) external view returns (bool) {
        return _oracles.contains(oracle);
    }

    /**
     * @notice Get the oracle in the whitelist at the specified index.
     * @param index The index of the oracle in the whitelist.
     * @return The address of the oracle.
     */
    function oraclesWhitelist(uint256 index) external view returns (address) {
        return _oraclesWhitelist.at(index);
    }

    /**
     * @notice Get the number of oracles in the whitelist.
     * @return The number of oracles in the whitelist.
     */
    function oraclesWhitelistCount() external view returns (uint256) {
        return _oraclesWhitelist.length();
    }

    /**
     * @notice Check if the oracle exists in the oracles whitelist.
     * @param oracle The address of the oracle.
     * @return A boolean indicating if the oracle exists in the whitelist.
     */
    function oraclesWhitelistContains(address oracle) external view returns (bool) {
        return _oraclesWhitelist.contains(oracle);
    }

    /**
     * @notice Get the swapper configuration values.
     * @return connector The swapper connector used.
     * @return path The path used for swapping.
     */
    function swapper() external view returns (ISwapperConnector connector, bytes memory path) {
        return (_swapper.swapperConnector, _swapper.path);
    }

    /**
     * @notice Constructor for the CoreConfiguration contract.
     * @param immutableConfiguration_ The initial configuration settings for immutable components.
     * @param discount_ The initial NFT discount levels.
     * @param feeConfiguration_ The initial fee configuration settings.
     * @param limitsConfiguration_ The initial limits configuration settings.
     * @param swapper_ The initial swapper configuration settings.
     */
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
        require(
            address(immutableConfiguration_.utils) != address(0),
            "CoreConfiguration: Utils is zero address"
        );
        _immutableConfiguration = immutableConfiguration_;
        _updateDiscount(discount_);
        _updateFeeConfiguration(feeConfiguration_);
        _updateLimitsConfiguration(limitsConfiguration_);
        _updateSwapper(swapper_);
    }

    /**
     * @notice Add keepers to the keepers set.
     * @param keepers_ An array of keeper addresses to add.
     * @return A boolean indicating if the keepers were added successfully.
     */
    function addKeepers(address[] memory keepers_) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < keepers_.length; i++) {
            address keeper_ = keepers_[i];
            require(keeper_ != address(0), "CoreConfiguration: Keeper is zero address");
            _keepers.add(keeper_);
        }
        emit KeepersAdded(keepers_);
        return true;
    }

    /**
     * @notice Add oracles to the oracles set and whitelist.
     * @param oracles_ An array of oracle addresses to add.
     * @return A boolean indicating if the oracles were added successfully.
     */
    function addOracles(address[] memory oracles_) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < oracles_.length; i++) {
            _oracles.add(oracles_[i]);
            _oraclesWhitelist.add(oracles_[i]);
        }
        emit OraclesAdded(oracles_);
        return true;
    }

    /**
     * @notice Remove keepers from the keepers set.
     * @param keepers_ An array of keeper addresses to remove.
     * @return A boolean indicating if the keepers were removed successfully.
     */
    function removeKeepers(address[] memory keepers_) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < keepers_.length; i++) {
            address keeper_ = keepers_[i];
            _keepers.remove(keeper_);
        }
        emit KeepersRemoved(keepers_);
        return true;
    }

    /**
     * @notice Remove oracles from the oracles set.
     * @param oracles_ An array of oracle addresses to remove.
     * @return A boolean indicating if the oracles were removed successfully.
     */
    function removeOracles(address[] memory oracles_) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < oracles_.length; i++) {
            _oracles.remove(oracles_[i]);
        }
        emit OraclesRemoved(oracles_);
        return true;
    }

    /**
     * @notice Remove oracles from the oracles whitelist.
     * @param oracles_ An array of oracle addresses to remove from the whitelist.
     * @return A boolean indicating if the oracles were removed from the whitelist successfully.
     */
    function removeOraclesWhitelist(address[] memory oracles_) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < oracles_.length; i++) {
            _oraclesWhitelist.remove(oracles_[i]);
        }
        emit OraclesWhitelistRemoved(oracles_);
        return true;
    }

    /**
     * @notice Update the NFT discount levels.
     * @param discount_ The new NFTDiscountLevel values.
     * @return A boolean indicating if the discount levels were updated successfully.
     */
    function updateDiscount(NFTDiscountLevel memory discount_) external onlyOwner returns (bool) {
        _updateDiscount(discount_);
        return true;
    }

    /**
     * @notice Update the fee configuration values.
     * @param config The new FeeConfiguration values.
     * @return A boolean indicating if the fee configuration was updated successfully.
     */
    function updateFeeConfiguration(FeeConfiguration memory config) external onlyOwner returns (bool) {
        _updateFeeConfiguration(config);
        return true;
    }

    /**
     * @notice Update the limits configuration values.
     * @param config The new LimitsConfiguration values.
     * @return A boolean indicating if the limits configuration was updated successfully.
     */
    function updateLimitsConfiguration(LimitsConfiguration memory config) external onlyOwner returns (bool) {
        _updateLimitsConfiguration(config);
        return true;
    }

    /**
     * @notice Update the swapper configuration values.
     * @param swapper_ The new Swapper values.
     * @return A boolean indicating if the swapper configuration was updated successfully.
     */
    function updateSwapper(Swapper memory swapper_) external onlyOwner returns (bool) {
        _updateSwapper(swapper_);
        return true;
    }

    /**
     * @notice Updates the NFT discount levels.
     * @param discount_ The new NFT discount levels.
     */
    function _updateDiscount(NFTDiscountLevel memory discount_) private {
        require(
            discount_.bronze <= DIVIDER && discount_.silver <= DIVIDER && discount_.gold <= DIVIDER,
            "CoreConfiguration: Invalid discount value"
        );
        _discount = discount_;
        emit DiscountUpdated(discount_);
    }

    /**
     * @notice Updates the fee configuration.
     * @param config The new fee configuration.
     */
    function _updateFeeConfiguration(FeeConfiguration memory config) private {
        require(config.feeRecipient != address(0), "CoreConfiguration: Recipient is zero address");
        require(config.protocolFee <= MAX_PROTOCOL_FEE, "CoreConfiguration: Protocol fee gt max");
        require(config.flashloanFee <= MAX_FLASHLOAN_FEE, "CoreConfiguration: Flashloan fee gt max");
        _feeConfiguration = config;
        emit FeeConfigurationUpdated(config);
    }

    /**
     * @notice Updates the limits configuration.
     * @param config The new limits configuration.
     */
    function _updateLimitsConfiguration(LimitsConfiguration memory config) private {
        require(config.minStableAmount > 0, "CoreConfiguration: Min stable is not positive");
        require(config.minOrderRate > 0, "CoreConfiguration: Min rate is not positive");
        require(config.maxOrderRate >= config.minOrderRate, "CoreConfiguration: Max order rate lt min");
        require(config.maxDuration >= config.minDuration, "CoreConfiguration: Max duration lt min");
        _limitsConfiguration = config;
        emit LimitsConfigurationUpdated(config);
    }

    /**
     * @notice Updates the swapper configuration.
     * @param swapper_ The new swapper configuration.
     */
    function _updateSwapper(Swapper memory swapper_) private {
        require(address(swapper_.swapperConnector) != address(0), "CoreConfiguration: Connector is zero address");
        require(swapper_.path.length > 0, "CoreConfiguration: Path is zero address");
        _swapper = swapper_;
        emit SwapperUpdated(swapper_);
    }
}

