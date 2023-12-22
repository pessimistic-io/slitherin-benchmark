// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.3;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./ERC20.sol";
import "./SafeMath.sol";
import "./IMarket.sol";
import "./IComptroller.sol";
import "./Price.sol";
import "./BlockLock.sol";

/// @title Market Asset Holder
/// @notice Registers the xAssets as collaterals put into the protocol by each borrower
/// @dev There should be as many markets as collaterals the admins want for the protocol
contract Market is
    Initializable,
    OwnableUpgradeable,
    BlockLock,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IMarket
{
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public underlyingAssetAddress;
    address public assetPriceAddress;
    address public comptroller;

    uint256 private assetDecimalMultiplier;
    uint256 private collateralFactor;
    uint256 private collateralCap;
    /// @notice Tells if the market is active for borrowers to collateralize their assets
    bool public marketActive;

    mapping(address => uint256) collaterals;

    uint256 private constant FACTOR = 1e18;
    uint256 private constant PRICE_DECIMALS_CORRECTION = 1e12;
    uint256 private constant RATIOS = 1e16;

    /// @notice Emit collateralCap update event
    event UpdateCollateralCap(uint256 collateralCap);
    /// @notice Emit collateralFactor update event
    event UpdateCollateralFactor(uint256 collateralFactor);
    /// @notice Emit collateralizationActive update event
    event UpdateCollateralizationActive(bool active);
    /// @notice Emit comptroller update event
    event UpdateComptroller(address indexed comptroller);

    event Collateralize(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    /// @dev Allows only comptroller to perform specific functions
    modifier onlyComptroller() {
        require(msg.sender == comptroller, "You are not allowed to perform this action");
        _;
    }

    /// @notice Upgradeable smart contract constructor
    /// @dev Initializes this collateral market
    /// @param _assetPriceAddress (address) The xAsset Price address
    /// @param _collateralFactor (uint256) collateral factor for this market Ex. 35% should be entered as 35
    /// @param _collateralCap (uint256) collateral cap for this market  Ex. 120e18 must be understood as 120 xKNC or xINCH
    function initialize(
        address _assetPriceAddress,
        uint256 _collateralFactor,
        uint256 _collateralCap
    ) external initializer {
        require(_assetPriceAddress != address(0));
        __Ownable_init();
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();

        assetPriceAddress = _assetPriceAddress;
        underlyingAssetAddress = Price(_assetPriceAddress).underlyingAssetAddress();
        assetDecimalMultiplier = 10**(uint256(18).sub(ERC20(underlyingAssetAddress).decimals()));
        collateralFactor = _collateralFactor.mul(RATIOS);
        collateralCap = _collateralCap;
        marketActive = true;
    }

    /// @notice Returns the registered collateral factor
    /// @return  (uint256) collateral factor for this market Ex. 35 must be understood as 35%
    function getCollateralFactor() external view override returns (uint256) {
        return collateralFactor.div(RATIOS);
    }

    /// @notice Allows only owners of this market to set a new collateral factor
    /// @param _collateralFactor (uint256) collateral factor for this market Ex. 35% should be entered as 35
    function setCollateralFactor(uint256 _collateralFactor) external override onlyOwner {
        collateralFactor = _collateralFactor.mul(RATIOS);
        emit UpdateCollateralFactor(_collateralFactor);
    }

    /// @notice Returns the registered collateral cap
    /// @return  (uint256) collateral cap for this market
    function getCollateralCap() external view override returns (uint256) {
        return collateralCap;
    }

    /// @notice Allows only owners of this market to set a new collateral cap
    /// @param _collateralCap (uint256) collateral factor for this market
    function setCollateralCap(uint256 _collateralCap) external override onlyOwner {
        collateralCap = _collateralCap;
        emit UpdateCollateralCap(_collateralCap);
    }

    /// @notice Owner function: pause all user actions
    function pauseContract() external onlyOwner {
        _pause();
    }

    /// @notice Owner function: unpause
    function unpauseContract() external onlyOwner {
        _unpause();
    }

    /// @dev Exempts an address from blocklock
    /// @param lockAddress The address to exempt
    function exemptFromBlockLock(address lockAddress) external onlyOwner {
        _exemptFromBlockLock(lockAddress);
    }

    /// @dev Removes exemption for an address from blocklock
    /// @param lockAddress The address to remove exemption
    function removeBlockLockExemption(address lockAddress) external onlyOwner {
        _removeBlockLockExemption(lockAddress);
    }

    /// @notice Borrowers can collateralize their assets using this function
    /// @dev The amount is meant to hold underlying assets tokens Ex. 120e18 must be understood as 120 xKNC or xINCH
    /// @param _amount (uint256) underlying tokens to be collateralized
    function collateralize(uint256 _amount) external override notLocked(msg.sender) nonReentrant whenNotPaused {
        require(_amount > 0, "The amount should not be zero");
        require(marketActive, "This market is not active now, you can not perform this action");
        uint256 parsedAmount = convertTo18(_amount);
        require(
            convertTo18(IERC20(underlyingAssetAddress).balanceOf(address(this)).add(_amount)) <= collateralCap,
            "You reached the maximum cap for this market"
        );
        lock(msg.sender);
        if (collaterals[msg.sender] == 0) {
            IComptroller(comptroller).addBorrowerMarket(msg.sender, address(this));
        }
        collaterals[msg.sender] = collaterals[msg.sender].add(parsedAmount);
        IERC20Upgradeable(underlyingAssetAddress).safeTransferFrom(msg.sender, address(this), _amount);

        emit Collateralize(msg.sender, _amount);
    }

    /// @notice Borrowers can fetch how many underlying asset tokens they have collateralized
    /// @dev The return value has 18 decimals
    /// @return  (uint256) underlying asset tokens collateralized by the borrower
    function collateral(address _borrower) public view override returns (uint256) {
        return collaterals[_borrower];
    }

    /// @notice Anyone can know how much a borrower can borrow in USDC terms according to the oracles prices for their collaterals
    /// @dev USDC here has nothing to do with the decimals the actual USDC smart contract has. Since it's a market, always assume 18 decimals
    /// @dev The return value has 18 decimals
    /// @param _borrower (address) borrower's address
    /// @return  (uint256) amount of USDC tokens that the borrower has access to
    function borrowingLimit(address _borrower) public view override returns (uint256) {
        uint256 assetValueInUSDC = Price(assetPriceAddress).getPrice(); // Price has 12 decimals
        return
            collaterals[_borrower].mul(assetValueInUSDC).mul(collateralFactor).div(PRICE_DECIMALS_CORRECTION).div(
                FACTOR
            );
    }

    /// @notice Owners of this market can tell which comptroller is managing this market
    /// @dev Several interactions between liquidity pool and markets are handled by the comptroller
    /// @param _comptroller (address) comptroller's address
    function setComptroller(address _comptroller) external override onlyOwner {
        require(_comptroller != address(0));
        comptroller = _comptroller;
        emit UpdateComptroller(_comptroller);
    }

    /// @notice Owners can decide wheather or not this market allows borrowers to collateralize
    /// @dev True is an active market, false is an inactive market
    /// @param _active (bool) flag indicating the market active state
    function setCollateralizationActive(bool _active) external override onlyOwner {
        marketActive = _active;
        emit UpdateCollateralizationActive(_active);
    }

    /// @notice Sends tokens from a borrower to a liquidator upon liquidation
    /// @dev This action is triggered by the comptroller
    /// @param _liquidator (address) liquidator's address
    /// @param _borrower (address) borrower's address
    /// @param _amount (uint256) amount in USDC terms to be transferred to the liquidator
    function sendCollateralToLiquidator(
        address _liquidator,
        address _borrower,
        uint256 _amount
    ) external override onlyComptroller {
        uint256 tokens = _amount.mul(PRICE_DECIMALS_CORRECTION).div(Price(assetPriceAddress).getPrice());
        uint256 collateralAmount = collaterals[_borrower];
        require(collateralAmount >= tokens, "Borrower does not have enough collateral");
        collaterals[_borrower] = collateralAmount.sub(tokens);
        IERC20Upgradeable(underlyingAssetAddress).safeTransfer(_liquidator, convertFrom18(tokens));
    }

    /// @notice Borrowers can withdraw their collateral assets
    /// @dev Borrowers can only withdraw their collaterals if they have enough tokens and there is no active loan
    /// @param _amount (uint256) underlying tokens to be withdrawn
    function withdraw(uint256 _amount) external notLocked(msg.sender) nonReentrant whenNotPaused {
        uint256 parsedAmount = convertTo18(_amount);
        uint256 collateralAmount = collaterals[msg.sender];
        require(collateralAmount >= parsedAmount, "You have not collateralized that much");

        lock(msg.sender);
        collateralAmount = collateralAmount.sub(parsedAmount);
        collaterals[msg.sender] = collateralAmount;

        uint256 healthRatioAfterWithdraw = IComptroller(comptroller).getHealthRatio(msg.sender);
        require(
            healthRatioAfterWithdraw >= 100,
            "You can not withdraw your collateral when you are undercollateralized"
        );

        if (collateralAmount == 0) {
            IComptroller(comptroller).removeBorrowerMarket(msg.sender, address(this));
        }
        IERC20Upgradeable(underlyingAssetAddress).safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    /// @dev Convert to 18 decimals from token defined decimals.
    function convertTo18(uint256 _amount) private view returns (uint256) {
        return _amount.mul(assetDecimalMultiplier);
    }

    /// @dev Convert from 18 decimals to token defined decimals.
    function convertFrom18(uint256 _amount) private view returns (uint256) {
        return _amount.div(assetDecimalMultiplier);
    }
}

