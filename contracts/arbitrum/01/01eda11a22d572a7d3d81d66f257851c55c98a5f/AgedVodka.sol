// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./OwnableUpgradeable.sol";
import "./ERC4626.sol";
import "./SafeERC20Upgradeable.sol";
import "./ERC4626Upgradeable.sol";
import "./MathUpgradeable.sol";


import "./IRewardRouterV2.sol";
import "./IVault.sol";
import "./IGlpManager.sol";
import "./IGlpRewardHandler.sol";

import "./console.sol";

contract AgedVodka is ERC4626Upgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

    address public feeReceiver;
    uint256 public mFee;
    uint256 public lastHarvested;
    uint256 public lastHarvestedGap;
    uint256 public minCompoundAmount;

    uint256 public constant DENOMINATOR = 1000;
    uint256 public AgedVodka_DEFAULT_PRICE;
    uint256 public totalGLP;
    

    StrategyAddresses public strategyAddresses;

    struct StrategyAddresses {
        address rewardRouterV2;
        address glp;
        address glpManager;
        address WETH;
        address rewardVault;
        address glpRewardHandler;
    }

    uint256[50] private __gaps;

    modifier noZeroValues(uint256 assetsOrShares) {
        require(assetsOrShares > 0, "VALUE_0");
        _;
    }

    event ProtocolFeeChanged(address newFeeReceiver, uint256 newmFee);
    event Lend(address indexed user, uint256 amount);
    event RepayDebt(address indexed user, uint256 debtAmount, uint256 amountPaid);
    event GLPGifterAllowed(address indexed gifter, bool status);
    event UtilRateChanged(uint256 utilRate);
    event RewardRouterContractChanged(address newVault, address glpRewardHandler, address rewardVault);
    event HarvestAndCompound(uint256 toCompound, uint256 totalGLP, uint256 glpAmount, uint256 harvested, uint256 feeAmount);
    event HarvestGapChanged(uint256 lastHarvestedGap);
    event CompoundAmountChanged(uint256 minCompoundAmount);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _rewardRouterV2,
        address _rewardsVault,
        address _weth,
        address _glpstaked) external initializer {
        AgedVodka_DEFAULT_PRICE = 1e18;
        minCompoundAmount = 0.001 ether;

        strategyAddresses.glp = _glpstaked;
        strategyAddresses.glpManager = IRewardRouterV2(_rewardRouterV2).glpManager();
        strategyAddresses.WETH = _weth;
        strategyAddresses.rewardVault = _rewardsVault;
        strategyAddresses.rewardRouterV2 = _rewardRouterV2;

        __Ownable_init();
        __ERC4626_init(IERC20Upgradeable(_glpstaked));
        __ERC20_init("AgedVodka", "AVODKA");
    }

    /** ---------------- View functions --------------- */

    function balanceOfGLP() public view returns (uint256) {
        return totalGLP;
    }

    function getAgedVodkaPrice() public view returns (uint256) {
        uint256 currentPrice;
        if (totalAssets() == 0) {
            currentPrice = AgedVodka_DEFAULT_PRICE;
        } else {
            currentPrice = totalAssets().mulDiv(AgedVodka_DEFAULT_PRICE, totalSupply());
        }
        return currentPrice;
    }

    function totalAssets() public view virtual override returns (uint256) {
        return totalGLP;
    }

    /** ----------- Change onlyOwner functions ------------- */
    
    function setStrategyContracts(
        address _rewardRouterV2,
        address _rewardVault,
        address _glpRewardHandler,
        address _glpStaked
    ) external onlyOwner {
        require(_rewardRouterV2 != address(0) &&
        _rewardVault != address(0) &&
        _glpRewardHandler != address(0) &&
        _glpStaked != address(0), "No Zero Addresses");
        
        strategyAddresses.rewardRouterV2 = _rewardRouterV2;
        strategyAddresses.rewardVault = _rewardVault;
        strategyAddresses.glp = _glpStaked;
        strategyAddresses.glpManager = IRewardRouterV2(_rewardRouterV2).glpManager();
        strategyAddresses.glpRewardHandler = _glpRewardHandler;

        emit RewardRouterContractChanged(_rewardRouterV2, _glpRewardHandler, _rewardVault);
    }

    function setProtocolFee(
        address _feeReceiver,
        uint256 _mFee
    ) external onlyOwner {
        require(_mFee > 0 && _mFee <= DENOMINATOR, "Invalid mFee fees");
        require(_feeReceiver != address(0), "Invalid fee receiver");
        mFee = _mFee;
        feeReceiver = _feeReceiver;
        emit ProtocolFeeChanged(_feeReceiver, _mFee);
    }

    function setHarvestedGap(uint256 _lastHarvestedGap) external onlyOwner {
        require(_lastHarvestedGap > 0, "Invalid harvested gap");
        lastHarvestedGap = _lastHarvestedGap;
        emit HarvestGapChanged(_lastHarvestedGap);
    }

    function setMinCompoundAmount(uint256 _minCompoundAmount) external onlyOwner {
        require(_minCompoundAmount > 0, "Invalid min compound amount");
        minCompoundAmount = _minCompoundAmount;
        emit CompoundAmountChanged(_minCompoundAmount);
    }

    /** ----------- Public functions ------------- */
    //Test function only
    function getGLP(uint256 _amount) public onlyOwner {
        address asset = strategyAddresses.WETH;
        console.log("strategyAddresses.WETH", strategyAddresses.WETH,strategyAddresses.rewardRouterV2);
        IERC20Upgradeable(asset).transferFrom(msg.sender, address(this), _amount);
        console.log("Passed transfer");
        IERC20Upgradeable(asset).safeIncreaseAllowance(strategyAddresses.glpManager, _amount);
        console.log("Getting glp", strategyAddresses.rewardRouterV2);
        uint256 glpAmount = IRewardRouterV2(strategyAddresses.rewardRouterV2).mintAndStakeGlp(asset, _amount, 0, 0);
        console.log("Passed",glpAmount);
        IERC20Upgradeable(strategyAddresses.glp).safeTransfer(msg.sender, glpAmount);
    }

    //OnlyAllowed if last time harvested + gap has passed
    function handleAndCompoundRewards() public {
        if (block.timestamp > lastHarvested + lastHarvestedGap) {
            _handleAndCompoundRewards();
        }
    }

    function deposit(uint256 _assets, address _receiver) public override noZeroValues(_assets) returns (uint256) {
        if (totalAssets() > 0) {
            _handleAndCompoundRewards();
        }
        require(_assets <= maxDeposit(msg.sender), "ERC4626: deposit more than max");

        uint256 shares;
        if (totalSupply() == 0) {
            require(_assets > 1000, "Not Enough Shares for first mint");
            uint256 SCALE = 10 ** decimals() / 10 ** 18;
            shares = (_assets - 1000) * SCALE;
            _mint(address(this), 1000 * SCALE);
        } else {
            shares = previewDeposit(_assets);
        }

        _deposit(_msgSender(), msg.sender, _assets, shares);
        totalGLP += _assets;
        console.log("_assets", _assets);
        console.log("Total GLP: %s", totalGLP);

        return shares;
    }

    function withdraw(
        uint256 _assets,
        address _receiver,
        address _owner
    ) public override noZeroValues(_assets) returns (uint256) {
        _handleAndCompoundRewards();
        require(_assets <= maxWithdraw(msg.sender), "ERC4626: withdraw more than max");
        require(balanceOfGLP() > _assets, "Insufficient balance in vault");
        
        uint256 shares = previewWithdraw(_assets);
        console.log("Shares: %s", shares);
        console.log("_assets", _assets);

        _withdraw(_msgSender(), msg.sender, msg.sender, _assets, shares);
        totalGLP -= _assets;
        return shares;
    }

    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        revert("Not used");
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256) {
        revert("Not used");
    }

    /** ----------- Internal functions ------------- */
    function _handleAndCompoundRewards() internal {
        IRewardRouterV2(strategyAddresses.rewardVault).handleRewards(true, true, true, true, true, true, false);
        uint256 harvested = IERC20Upgradeable(strategyAddresses.WETH).balanceOf(address(this));

        console.log("harvested", harvested);

        if (harvested >= minCompoundAmount) {
            uint256 feeAmount = harvested * mFee / DENOMINATOR;
            IERC20Upgradeable(strategyAddresses.WETH).safeTransfer(feeReceiver, feeAmount);
            uint256 toCompound = harvested - feeAmount;
            console.log("feeAmount", feeAmount);
            console.log("toCompound", toCompound);

            address asset = strategyAddresses.WETH;
            IERC20Upgradeable(asset).safeIncreaseAllowance(strategyAddresses.glpManager, toCompound);
            uint256 glpAmount = IRewardRouterV2(strategyAddresses.rewardRouterV2).mintAndStakeGlp(asset, toCompound, 0, 0);
            console.log("totalGLP", totalGLP);
            totalGLP += glpAmount;
            console.log("totalGLP", totalGLP);

            lastHarvested = block.timestamp;
            emit HarvestAndCompound(toCompound, totalGLP, glpAmount, harvested, feeAmount);
        }
    }
}

