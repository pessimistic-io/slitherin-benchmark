// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;
import "./ERC4626Metadata.sol";
import "./IMarket.sol";
import "./IVault.sol";
import "./ERC20PresetMinterPauser.sol";
import "./extensions_IERC20Metadata.sol";
import "./Ownable.sol";
import "./Math.sol";
import "./SafeERC20.sol";

contract Vault is IVault, ERC4626Metadata, Ownable {

    using Math for uint256;
    using SafeERC20 for IERC20;

    // These will change to allow multiple markets
    address private _market;
    address private _self;
    uint256 private _rate;

    constructor(IERC20Metadata asset_)
    ERC4626Metadata(
        asset_
    ) 
    ERC20(
        string(abi.encodePacked("HL ", asset_.name())),
        string(abi.encodePacked("HL", asset_.symbol()))
    ) {
        require(
            address(asset_) != address(0),
            "Underlying address is invalid"
        );
        _self = address(this);
    }

    function getOwner() external view returns (address) {
		return owner();
	}

    function removeMarket() external onlyOwner {
        _rate = 0;
        IERC20(asset()).approve(_market, 0);

        emit MarketRemoved(_market);

        _market = address(0);
    }

    function setMarket(address market, uint256 max, uint256 rate) external onlyOwner {
        require(_market == address(0), "setMarket: Market already set");
        require(rate >= 100_000, "setMarket: Rate must be greater than 100,000");
        _market = market;
        _rate = rate;
        IERC20(asset()).approve(_market, max);

        emit MarketSet(market, rate);
    }

    function getMarket() external view returns (address) {
        return _market;
    }

    function getPerformance() external view returns (uint256) {
        return _getPerformance();
    }

    function _getPerformance() private view returns (uint256) {
        uint256 underlyingBalance = totalAssets();
        if (underlyingBalance > 0)
            return (totalSupply() * 100) / underlyingBalance;

        return 0;
    }

    function getRate() external view returns (uint256) {
        return _rate;
    }

    // If receiver is omitted, use the sender
    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        require(receiver != _self, "deposit: The receiver cannot be the vault");
        if (receiver == address(0)) receiver = _msgSender();
        return super.deposit(assets, receiver);
    }

    function getMarketAllowance() external view withMarket returns (uint256) {
        // TODO: This will change to allow multiple markets, using msg.sender
        uint256 allowance = ERC20(asset()).allowance(_self, _market);
        if (allowance > totalAssets()) {
            return totalAssets();
        }
        
        return allowance;
    }

    function totalAssetsLocked() external view returns (uint256) {
        return IMarket(_market).getTotalExposure();
    }

    /** @dev See {IERC4626-maxRedeem}. */
    function maxRedeem(address owner) public view override returns (uint256) {
        if (totalAssets() == 0) return 0;

        // A fraction of the total assets is locked is locked for the owner, proportional to their holdings.
        uint256 shareBalance = balanceOf(owner);
        uint256 sharesLockedForOwner = shareBalance / totalAssets();
        return shareBalance - sharesLockedForOwner;
    }

    modifier onlyMarket() {
        require(_market != address(0), "onlyMarket: Market not set");
        require(
            msg.sender == _market,
            "onlyMarket: Only the market can call this function"
        );
        _;
    }

    modifier withMarket() {
        require(
            _market != address(0),
            "withMarket: Not allowed until market is set"
        );
        _;
    }

    event MarketSet(address indexed market, uint256 rate);
    event MarketRemoved(address indexed market);
}

