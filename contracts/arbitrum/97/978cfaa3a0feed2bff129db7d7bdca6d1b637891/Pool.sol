// SPDX-License-Identifier: MIT

pragma solidity >0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

import "./ITreasury.sol";
import "./IOracle.sol";
import "./IPool.sol";

interface IArbiTenToken {
    function totalSupply() external view returns (uint);
    function mint(address _to, uint _amount) external;
    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint amount) external returns (bool);
    function poolBurnFrom(address _address, uint _amount) external;
    function poolMint(address _address, uint _amount) external;
}

interface I10SHAREToken {
    function mint(address _to, uint _amount) external;
    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint amount) external returns (bool);
    function poolBurnFrom(address _address, uint _amount) external;
    function poolMint(address _address, uint _amount) external;
}

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract Pool is Ownable, ReentrancyGuard, IPool {
    using SafeMath for uint;
    using SafeERC20 for ERC20;

    /* ========== STATE VARIABLES ========== */

    address public collateral;
    address public ArbiTen;
    address public treasury;
    address public _10SHARE;

    address public constant wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    uint public lastEpochForMinting = type(uint).max;
    uint public mintingDailyAllowance = 110e18;
    uint public mintedArbiTenSoFarInEpoch = 0;
    uint public mintIncreasePerEpoch = 10e18;

    uint public lastEpochForRedeem = type(uint).max;
    uint public redeemStartEpoch;
    uint public redeemDailyAllowance = 50e18;
    uint public redeemedArbiTenSoFarInEpoch = 0;
    uint public redeemIncreasePerEpoch = 10e18;

    mapping(address => uint) public redeem_share_balances;
    mapping(address => uint) public redeem_collateral_balances;

    uint public unclaimed_pool_collateral;
    uint public unclaimed_pool_share;

    mapping(address => uint) public last_redeemed;

    uint public netMinted;
    uint public netRedeemed;

    // Constants for various precisions
    uint private constant PRICE_PRECISION = 1e18;
    uint private constant COLLATERAL_RATIO_MAX = 1e6;

    // Number of decimals needed to get to 18
    uint private missing_decimals;

    // Pool_ceiling is the total units of collateral that a pool contract can hold
    uint public pool_ceiling = 0;

    // Number of blocks to wait before being able to collectRedemption()
    uint public redemption_delay = 1;

    uint public twapPriceScalingPercentage = 980000; // 98% to start

    // AccessControl state variables
    bool public mint_paused = true;
    bool public redeem_paused = false;
    bool public migrated = false;


    /* ========== MODIFIERS ========== */


    modifier notMigrated() {
        require(!migrated, "migrated");
        _;
    }

    modifier onlyTreasury() {
        require(msg.sender == treasury, "!treasury");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _ArbiTen,
        address __10SHARE,
        address _collateral,
        address _treasury,
        uint _pool_ceiling,
        uint _redeemStartEpoch
    ) public {

        ArbiTen = _ArbiTen;
        _10SHARE = __10SHARE;
        collateral = _collateral;
        treasury = _treasury;
        pool_ceiling = _pool_ceiling;
        missing_decimals = uint(18).sub(ERC20(_collateral).decimals());

        redeemStartEpoch = _redeemStartEpoch;
    }

    /* ========== VIEWS ========== */

    // Returns ArbiTen value of collateral held in this pool
    function collateralArbiTenBalance() external view override returns (uint) {
        return (ERC20(collateral).balanceOf(address(this)).sub(unclaimed_pool_collateral)).mul(10**missing_decimals);//.mul(collateral_usd_price).div(PRICE_PRECISION);
    }

    function info()
        external
        view
        returns (
            uint,
            uint,
            uint,
            uint,
            uint,
            bool,
            bool
        )
    {
        return (
            pool_ceiling, // Ceiling of pool - collateral-amount
            ERC20(collateral).balanceOf(address(this)), // amount of COLLATERAL locked in this contract
            unclaimed_pool_collateral, // unclaimed amount of COLLATERAL
            unclaimed_pool_share, // unclaimed amount of SHARE
            getCollateralPrice(), // collateral price
            mint_paused,
            redeem_paused
        );
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function getCollateralPrice() public pure override returns (uint) {
        // only for ETH
        return PRICE_PRECISION;
    }

    function getCollateralToken() external view override returns (address) {
        return collateral;
    }

    function netSupplyMinted() external view override returns (uint) {
        if (netMinted > netRedeemed)
            return netMinted.sub(netRedeemed);
        return 0;
    }

    function mint(
        uint _collateral_amount,
        uint _share_amount,
        uint ArbiTen_out_min
    ) external payable notMigrated {
        require(mint_paused == false, "Minting is paused");
        require(block.timestamp >= ITreasury(treasury).startTime(), "Minting hasnt started yet!");

        uint currentEpoch = ITreasury(treasury).epoch();

        if (lastEpochForMinting == type(uint).max) {
            lastEpochForMinting = currentEpoch;
        } else if (lastEpochForMinting < currentEpoch) {
            mintingDailyAllowance += (mintIncreasePerEpoch * (currentEpoch - lastEpochForMinting));
            lastEpochForMinting = currentEpoch;
            mintedArbiTenSoFarInEpoch = 0;
        }

        uint unwrappedETHGiven = msg.value;

        if (unwrappedETHGiven > 0) {
            _collateral_amount+= unwrappedETHGiven;
        }

        (uint ArbiTenPrice, uint _share_price, , uint _target_collateral_ratio, , , uint _minting_fee, ) = ITreasury(treasury).info();
        require(ERC20(collateral).balanceOf(address(this)).sub(unclaimed_pool_collateral).add(_collateral_amount) <= pool_ceiling, ">poolCeiling");
        uint _totalArbiTen_value = 0;
        uint _required_share_amount = 0;
        if (_target_collateral_ratio > 0) {
            uint _collateral_value = (_collateral_amount * (10**missing_decimals));//.mul(_price_collateral).div(PRICE_PRECISION);
            _totalArbiTen_value = _collateral_value.mul(COLLATERAL_RATIO_MAX).div(_target_collateral_ratio);
            if (_target_collateral_ratio < COLLATERAL_RATIO_MAX) {
                _required_share_amount = _totalArbiTen_value.sub(_collateral_value).mul(PRICE_PRECISION).div(_share_price);
            }
        } else {
            _totalArbiTen_value = _share_amount.mul(_share_price).div(PRICE_PRECISION);
            _required_share_amount = _share_amount;
        }

        // ArbiTen is 1/10 usd
        uint _actualArbiTen_amount = _totalArbiTen_value.sub((_totalArbiTen_value.mul(_minting_fee)).div(1e6)).mul(10);

        if (ArbiTenPrice > 1e17) {
            uint denominator = ArbiTenPrice.sub(1e17).mul(twapPriceScalingPercentage).div(1e6).add(1e17);
            _actualArbiTen_amount = _actualArbiTen_amount.mul(1e17).div(denominator);
        }

        require(mintedArbiTenSoFarInEpoch + _actualArbiTen_amount <= mintingDailyAllowance, "Epoch minting allowance exceeded!");

        mintedArbiTenSoFarInEpoch += _actualArbiTen_amount;

        require(ArbiTen_out_min <= _actualArbiTen_amount, ">slippage");

        if (_required_share_amount > 0) {
            require(_required_share_amount <= _share_amount, "<shareBalance");
            I10SHAREToken(_10SHARE).poolBurnFrom(msg.sender, _required_share_amount);
        }

        if (_collateral_amount > 0) {
            if (unwrappedETHGiven > 0) {
                IWETH(wethAddress).deposit{value: unwrappedETHGiven}();
            }
            ERC20(collateral).transferFrom(msg.sender, address(this), _collateral_amount);
        }

        netMinted = netMinted.add(_actualArbiTen_amount);

        IArbiTenToken(ArbiTen).poolMint(msg.sender, _actualArbiTen_amount);

        ITreasury(treasury).treasuryUpdates();

        emit Minted(msg.sender, _collateral_amount, _required_share_amount, _actualArbiTen_amount);
    }

    function redeem(
        uint ArbiTen_amount,
        uint _share_out_min,
        uint _collateral_out_min
    ) external notMigrated {
        require(redeem_paused == false, "Redeeming is paused");

        uint currentEpoch = ITreasury(treasury).epoch();        

        require(currentEpoch >= redeemStartEpoch, "Redemption is not enabled yet!");

        if (lastEpochForRedeem == type(uint).max) {
            lastEpochForRedeem = currentEpoch;
        } else if (lastEpochForRedeem < currentEpoch) {
            redeemDailyAllowance += (redeemIncreasePerEpoch * (currentEpoch - lastEpochForRedeem));
            lastEpochForRedeem = currentEpoch;
            redeemedArbiTenSoFarInEpoch = 0;
        }

        require(redeemedArbiTenSoFarInEpoch < redeemDailyAllowance, "Epoch redemption allowance Exceeded!");

        // If the daily limit is reached, let them redeem what they can
        if (redeemedArbiTenSoFarInEpoch + ArbiTen_amount > redeemDailyAllowance)
            ArbiTen_amount = redeemDailyAllowance - redeemedArbiTenSoFarInEpoch;

        redeemedArbiTenSoFarInEpoch += ArbiTen_amount;

        (, uint _share_price, , , uint _effective_collateral_ratio, , , uint _redemption_fee) = ITreasury(treasury).info();
        uint ArbiTen_amount_post_fee = ArbiTen_amount.sub((ArbiTen_amount.mul(_redemption_fee)).div(PRICE_PRECISION));
        uint _collateral_output_amount = 0;
        uint _share_output_amount = 0;

        if (ITreasury(treasury).using_effective_collateral_ratio()) {
            uint arbiTenTotalSupply = IArbiTenToken(ArbiTen).totalSupply();

            // Get balance of locked ArbiTen
            uint arbitenExcludedFromSupply = IArbiTenToken(ArbiTen).balanceOf(0xdA22b0A0F938525Fb9cbC8e9D447Bd106880E4a3);

            _effective_collateral_ratio = _effective_collateral_ratio.mul(arbiTenTotalSupply).div(arbiTenTotalSupply.sub(arbitenExcludedFromSupply));
        }

        if (_effective_collateral_ratio < COLLATERAL_RATIO_MAX) {
            uint _share_output_value = ArbiTen_amount_post_fee.sub(ArbiTen_amount_post_fee.mul(_effective_collateral_ratio).div(COLLATERAL_RATIO_MAX));
            _share_output_amount = _share_price == 0 ? 0 : _share_output_value.mul(PRICE_PRECISION).div(_share_price);
        }

        if (_effective_collateral_ratio > 0) {
            uint _collateral_output_value = ArbiTen_amount_post_fee.mul(_effective_collateral_ratio).div(10**missing_decimals).div(COLLATERAL_RATIO_MAX);
            _collateral_output_amount = _collateral_output_value;//.mul(PRICE_PRECISION).div(PRICE_PRECISION);
        }

        // ArbiTen is 1/10 usd
        _collateral_output_amount = _collateral_output_amount.div(10);
        _share_output_amount = _share_output_amount.div(10);

        // Check if collateral balance meets and meet output expectation
        require(_collateral_output_amount <= ERC20(collateral).balanceOf(address(this)).sub(unclaimed_pool_collateral), "<collateralBlanace");
        require(_collateral_out_min <= _collateral_output_amount && _share_out_min <= _share_output_amount, ">slippage");


        if (_collateral_output_amount > 0) {
            redeem_collateral_balances[msg.sender] = redeem_collateral_balances[msg.sender].add(_collateral_output_amount);
            unclaimed_pool_collateral = unclaimed_pool_collateral.add(_collateral_output_amount);
        }

        if (_share_output_amount > 0) {
            redeem_share_balances[msg.sender] = redeem_share_balances[msg.sender].add(_share_output_amount);
            unclaimed_pool_share = unclaimed_pool_share.add(_share_output_amount);
        }

        last_redeemed[msg.sender] = block.number;

        netRedeemed = netRedeemed.add(ArbiTen_amount);

        // Move all external functions to the end
        IArbiTenToken(ArbiTen).poolBurnFrom(msg.sender, ArbiTen_amount);
        if (_share_output_amount > 0) {
            I10SHAREToken(_10SHARE).poolMint(address(this), _share_output_amount);
        }

        ITreasury(treasury).treasuryUpdates();

        emit Redeemed(msg.sender, ArbiTen_amount, _collateral_output_amount, _share_output_amount);
    }

    function collectRedemption() external {
        // Redeem and Collect cannot happen in the same transaction to avoid flash loan attack
        require((last_redeemed[msg.sender].add(redemption_delay)) <= block.number, "<redemption_delay");

        bool _send_share = false;
        bool _send_collateral = false;
        uint _share_amount;
        uint _collateral_amount;

        // Use Checks-Effects-Interactions pattern
        if (redeem_share_balances[msg.sender] > 0) {
            _share_amount = redeem_share_balances[msg.sender];
            redeem_share_balances[msg.sender] = 0;
            unclaimed_pool_share = unclaimed_pool_share.sub(_share_amount);
            _send_share = true;
        }

        if (redeem_collateral_balances[msg.sender] > 0) {
            _collateral_amount = redeem_collateral_balances[msg.sender];
            redeem_collateral_balances[msg.sender] = 0;
            unclaimed_pool_collateral = unclaimed_pool_collateral.sub(_collateral_amount);
            _send_collateral = true;
        }

        if (_send_share) {
            ERC20(_10SHARE).transfer(msg.sender, _share_amount);
        }

        if (_send_collateral) {
            ERC20(collateral).transfer(msg.sender, _collateral_amount);
        }

        emit RedeemCollected(msg.sender, _collateral_amount, _share_amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // move collateral to new pool address
    function migrate(address _new_pool) external override nonReentrant onlyOwner notMigrated {
        migrated = true;
        uint availableCollateral = ERC20(collateral).balanceOf(address(this)).sub(unclaimed_pool_collateral);
        ERC20(collateral).safeTransfer(_new_pool, availableCollateral);
    }

    function toggleMinting() external onlyOwner {
        mint_paused = !mint_paused;
    }

    function toggleRedeeming() external onlyOwner {
        redeem_paused = !redeem_paused;
    }

    function setPoolCeiling(uint _pool_ceiling) external onlyOwner {
        pool_ceiling = _pool_ceiling;
    }

    function setTwapPriceScalingPercentage(uint _twapPriceScalingPercentage) external onlyOwner {
        require(_twapPriceScalingPercentage <= 2 * 1e6, "percentage out of range");
        twapPriceScalingPercentage = _twapPriceScalingPercentage;
    }

    function setRedemptionDelay(uint _redemption_delay) external onlyOwner {
        redemption_delay = _redemption_delay;
    }

    function setMintIncreasePerEpoch(uint _mintIncrease) external onlyOwner {
        emit MintIncreasePerEpochChanged(mintIncreasePerEpoch, _mintIncrease);
        mintIncreasePerEpoch = _mintIncrease;
    }

    function setMintingDailyAllowance(uint _mintingDailyAllowance) external onlyOwner {
        emit MintingDailyAllowanceChanged(mintingDailyAllowance, _mintingDailyAllowance);
        mintingDailyAllowance = _mintingDailyAllowance;
    }

    function setRedeemIncreasePerEpoch(uint _redeemIncrease) external onlyOwner {
        emit RedeemIncreasePerEpochChanged(redeemIncreasePerEpoch, _redeemIncrease);
        redeemIncreasePerEpoch = _redeemIncrease;
    }

    function setRedeemDailyAllowance(uint _redeemDailyAllowance) external onlyOwner {
        emit RedeemDailyAllowanceChanged(redeemDailyAllowance, _redeemDailyAllowance);
        redeemDailyAllowance = _redeemDailyAllowance;
    }

    function setTreasury(address _treasury) external onlyOwner {
        emit TreasuryTransferred(treasury, _treasury);
        treasury = _treasury;
    }

    // Transfer collateral to Treasury to execute strategies
    function transferCollateralToOperator(uint amount) external onlyOwner {
        require(amount > 0, "zeroAmount");
        ERC20(collateral).safeTransfer(msg.sender, amount);
    }

    // EVENTS

    event TreasuryTransferred(address previousTreasury, address newTreasury);

    event Minted(address indexed user, uint usdtAmountIn, uint _10SHAREAmountIn, uint ArbiTenAmountOut);
    event Redeemed(address indexed user, uint ArbiTenAmountIn, uint usdtAmountOut, uint _10SHAREAmountOut);
    event RedeemCollected(address indexed user, uint usdtAmountOut, uint _10SHAREAmountOut);

    event MintIncreasePerEpochChanged(uint oldValue, uint newValue);
    event MintingDailyAllowanceChanged(uint oldValue, uint newValue);

    event RedeemIncreasePerEpochChanged(uint oldValue, uint newValue);
    event RedeemDailyAllowanceChanged(uint oldValue, uint newValue);
}

