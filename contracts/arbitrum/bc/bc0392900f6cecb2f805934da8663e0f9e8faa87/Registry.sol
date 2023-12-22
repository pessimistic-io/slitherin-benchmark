// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import "./IMarket.sol";
import "./IVault.sol";
import "./IERC20Metadata.sol";

contract Registry {
    address[] public markets;
    address[] public vaults;

    mapping(address => address) private _vaultByAsset;
    mapping(address => address) private _markets; 

    address private immutable _owner;
    IERC20Metadata private immutable _token;
    uint256 private _threshold;

    function marketCount() external view returns (uint256) {
        return markets.length;
    }

    function vaultCount() external view returns (uint256) {
        return vaults.length;
    }

    constructor(IERC20Metadata token) {
        _owner = msg.sender;
        _token = token;
    }

    function addVault(address vault) external onlyTokenHolders {
        assert(vault != address(0));
        address assetAddress = IVault(vault).asset();
        require(_vaultByAsset[assetAddress] == address(0), "addVault: Vault with this asset token already added");

        vaults.push(vault);
        _vaultByAsset[assetAddress] = vault; 

        emit VaultAdded(vault);
    }

    function removeVault(uint256 index, address vault) external onlyVaultOwner(vault) {
        if (index >= vaults.length) return;

        for (uint256 i = index; i < vaults.length - 1; i++){
            vaults[i] = vaults[i+1];
        }

        vaults.pop();

        delete _vaultByAsset[vault];
        emit VaultRemoved(vault);
    }

    function addMarket(address market) external onlyTokenHolders {
        require(
            _markets[market] == address(0),
            "addMarket: Market already added"
        );
        _markets[market] = market;
        markets.push(market);
        emit MarketAdded(market);
    }

    function removeMarket(uint256 index, address market) external onlyMarketOwner(market) {
        if (index >= markets.length) return;

        for (uint256 i = index; i < markets.length - 1; i++){
            markets[i] = markets[i+1];
        }

        markets.pop();

        delete _markets[market];
        emit MarketRemoved(market);
    }

    function setThreshold(uint256 threshold) external onlyOwner {
        require(threshold != _threshold, "setThreshold: Threshold already set");
        _threshold = threshold;
        emit ThresholdUpdated(threshold);
    }

    modifier onlyMarketOwner(address market) {
        require(
            IMarket(_markets[market]).getOwner() == msg.sender,
            "onlyMarketOwner: Caller is not the market owner"
        );
        _;
    }

    modifier onlyVaultOwner(address vault) {
        require(
            IVault(vault).getOwner() == msg.sender,
            "onlyVaultOwner: Caller is not the vault owner"
        );
        _;
    }

    modifier onlyTokenHolders() {
        require(
            _token.balanceOf(msg.sender) >= _threshold,
            "onlyTokenHolders: Caller does not hold enough tokens"
        );
        _;
    }

    modifier onlyOwner() {
        require(
            msg.sender == _owner,
            "onlyOwner: Caller is not the contract owner"
        );
        _;
    }

    event MarketAdded(address indexed market);
    event MarketRemoved(address indexed market);
    event ThresholdUpdated(uint256 threshold);
    event VaultAdded(address indexed vault);
    event VaultRemoved(address indexed vault);
}

