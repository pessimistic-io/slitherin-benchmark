// SPDX-License-Identifier: MIT

pragma solidity >0.6.12;

import "./Math.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

import "./Babylonian.sol";
import "./Operator.sol";
import "./ContractGuard.sol";
import "./IBasisAsset.sol";
import "./IOracle.sol";
import "./IBoardroom.sol";
import "./IPool.sol";


contract Treasury is ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint;

    // TODO: CHANGE ME Update time
    uint public constant PERIOD = 8 hours;

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;

    // flags
    bool public initialized = false;

    // epoch
    uint public startTime;
    uint public epoch = 0;
    uint public epochSupplyContractionLeft = 0;

    // exclusions from total supply
    address[] public excludedFromTotalSupply;

    // core components
    address public ArbiTen;
    address public _10BOND;
    address public _10SHARE;

    address public boardroom;
    address public ArbiTenOracle;
    address public _10SHAREOracle;

    uint public boardroomWithdrawFee;
    uint public boardroomStakeFee;

    // price
    uint public ArbiTenPriceOne;
    uint public ArbiTenPriceCeiling;

    uint public seigniorageSaved;

    uint public ArbiTenSupplyTarget;

    uint public maxSupplyExpansionPercent;
    uint public minMaxSupplyExpansionPercent;
    uint public bondDepletionFloorPercent;
    uint public seigniorageExpansionFloorPercent;
    uint public maxSupplyContractionPercent;
    uint public maxDebtRatioPercent;

    // 21 first epochs (1 week) with 3.5% expansion regardless of ArbiTen price
    uint public bootstrapEpochs;
    uint public bootstrapSupplyExpansionPercent;

    /* =================== Added variables =================== */
    uint public previousEpochArbiTenPrice;
    uint public maxDiscountRate; // when purchasing bond
    uint public maxPremiumRate; // when redeeming bond
    uint public discountPercent;
    uint public premiumThreshold;
    uint public premiumPercent;
    uint public mintingFactorForPayingDebt; // print extra ArbiTen during debt phase

    // 45% for Stakers in boardroom (THIS)
    // 45% for DAO fund
    // 2% for DEV fund
    // 8% for INSURANCE fund
    address public daoFund;
    uint public daoFundSharedPercent;

    address public devFund;
    uint public devFundSharedPercent;

    address public insuranceFund;
    uint public insuranceFundSharedPercent;

    address public equityFund;
    uint public equityFundSharedPercent;

    // pools
    address[] public pools_array;
    mapping(address => bool) public pools;

    // fees
    uint public redemption_fee; // 6 decimals of precision
    uint public minting_fee; // 6 decimals of precision

    // collateral_ratio
    uint public last_refresh_cr_timestamp;
    uint public target_collateral_ratio; // 6 decimals of precision
    uint public effective_collateral_ratio; // 6 decimals of precision
    uint public refresh_cooldown; // Seconds to wait before being able to run refreshCollateralRatio() again
    uint public ratio_step; // Amount to change the collateralization ratio by upon refreshCollateralRatio()
    uint public price_target; // The price of ArbiTen at which the collateral ratio will respond to; this value is only used for the collateral ratio mechanism and not for minting and redeeming which are hardcoded at $1
    uint public price_band; // The bound above and below the price target at which the Collateral ratio is allowed to drop
    bool public collateral_ratio_paused = false; // during bootstraping phase, collateral_ratio will be fixed at 100%
    bool public using_effective_collateral_ratio = true; // toggle the effective collateral ratio usage
    uint private constant COLLATERAL_RATIO_MAX = 1e6;

    // Constants for various precisions
    uint private constant PRICE_PRECISION = 1e18;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint at);
    event BurnedBonds(address indexed from, uint bondAmount);
    event RedeemedBonds(address indexed from, uint ArbiTenAmount, uint bondAmount);
    event BoughtBonds(address indexed from, uint ArbiTenAmount, uint bondAmount);
    event TreasuryFunded(uint timestamp, uint seigniorage);
    event BoardroomFunded(uint timestamp, uint seigniorage);
    event DaoFundFunded(uint timestamp, uint seigniorage);
    event DevFundFunded(uint timestamp, uint seigniorage);
    event InsuranceFundFunded(uint timestamp, uint seigniorage);
    event EquityFundFunded(uint timestamp, uint seigniorage);
    event Seigniorage(uint epoch, uint twap, uint expansion);
    event TransactionExecuted(address indexed target, uint value, string signature, bytes data);

    constructor() public {
        operator = msg.sender;
    }


    /* =================== Modifier =================== */

    modifier onlyOperator() {
        require(operator == msg.sender, "Treasury: caller is not the operator");
        _;
    }

    modifier checkCondition {
        require(block.timestamp >= startTime, "Treasury: not started yet");

        _;
    }

    modifier checkEpoch {
        require(block.timestamp >= nextEpochPoint(), "Treasury: not opened yet");

        _;

        epoch = epoch.add(1);
        epochSupplyContractionLeft = (getArbiTenPrice() > ArbiTenPriceCeiling) ? 0 : getArbiTenCirculatingSupply().mul(maxSupplyContractionPercent).div(10000);
    }

    modifier checkOperator {
        require(
            IBasisAsset(ArbiTen).amIOperator() &&
                IBasisAsset(_10BOND).amIOperator() &&
                IBasisAsset(_10SHARE).amIOperator() &&
                IBasisAsset(boardroom).amIOperator(),
            "Treasury: need more permission"
        );

        _;
    }

    modifier notInitialized {
        require(!initialized, "Treasury: already initialized");

        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function isInitialized() public view returns (bool) {
        return initialized;
    }

    // epoch
    function nextEpochPoint() public view returns (uint) {
        return startTime.add(epoch.mul(PERIOD));
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
            uint,
            uint,
            uint
        )
    {
        return (getArbiTenUpdatedPrice(), get10SHAREPrice(), IERC20(ArbiTen).totalSupply(), target_collateral_ratio, effective_collateral_ratio, globalCollateralValue(), minting_fee, redemption_fee);
    }


    // Iterate through all pools and calculate all value of collateral in all pools globally
    function globalCollateralValue() public view returns (uint) {
        uint total_collateral_value = 0;
        for (uint i = 0; i < pools_array.length; i++) {
            // Exclude null addresses
            if (pools_array[i] != address(0)) {
                total_collateral_value = total_collateral_value.add(IPool(pools_array[i]).collateralArbiTenBalance());
            }
        }
        return total_collateral_value;
    }


    // Iterate through all pools and calculate all value of collateral in all pools globally
    function globalIronSupply() public view returns (uint) {
        uint total_ironArbiTen_minted_ = 0;
        for (uint i = 0; i < pools_array.length; i++) {
            // Exclude null addresses
            if (pools_array[i] != address(0)) {
                total_ironArbiTen_minted_ = total_ironArbiTen_minted_.add(IPool(pools_array[i]).netSupplyMinted());
            }
        }
        return total_ironArbiTen_minted_;
    }

    function calcEffectiveCollateralRatio() public view returns (uint) {
        if (!using_effective_collateral_ratio) {
            return target_collateral_ratio;
        }
        uint total_collateral_value = globalCollateralValue();
        uint total_supplyArbiTen = IERC20(ArbiTen).totalSupply();
        // We are pegged to 1/10 ETH
        uint ecr = total_collateral_value.mul(10).mul(COLLATERAL_RATIO_MAX).div(total_supplyArbiTen);
        if (ecr > COLLATERAL_RATIO_MAX) {
            return COLLATERAL_RATIO_MAX;
        }
        return ecr;
    }

    function refreshCollateralRatio() external {
        require(collateral_ratio_paused == false, "Collateral Ratio has been paused");
        require(block.timestamp - last_refresh_cr_timestamp >= refresh_cooldown, "Must wait for the refresh cooldown since last refresh");

        uint currentArbiTen_price = getArbiTenPrice();

        // Step increments are 0.25% (upon genesis, changable by setRatioStep())
        if (currentArbiTen_price > price_target.add(price_band)) {
            // decrease collateral ratio
            if (target_collateral_ratio <= ratio_step) {
                // if within a step of 0, go to 0
                target_collateral_ratio = 0;
            } else {
                target_collateral_ratio = target_collateral_ratio.sub(ratio_step);
            }
        }
        // IRON price is below $0.1 - `price_band`. Need to increase `collateral_ratio`
        else if (currentArbiTen_price < price_target.sub(price_band)) {
            // increase collateral ratio
            if (target_collateral_ratio.add(ratio_step) >= COLLATERAL_RATIO_MAX) {
                target_collateral_ratio = COLLATERAL_RATIO_MAX; // cap collateral ratio at 1.000000
            } else {
                target_collateral_ratio = target_collateral_ratio.add(ratio_step);
            }
        }

        // If using ECR, then calcECR. If not, update ECR = TCR
        if (using_effective_collateral_ratio) {
            effective_collateral_ratio = calcEffectiveCollateralRatio();
        } else {
            effective_collateral_ratio = target_collateral_ratio;
        }

        last_refresh_cr_timestamp = block.timestamp;
    }

    // Check if the protocol is over- or under-collateralized, by how much
    function calcCollateralBalance() public view returns (uint _collateral_value, bool _exceeded) {
        uint total_collateral_value = globalCollateralValue();
        uint target_collateral_value = IERC20(ArbiTen).totalSupply().mul(target_collateral_ratio).div(COLLATERAL_RATIO_MAX);
        if (total_collateral_value >= target_collateral_value) {
            _collateral_value = total_collateral_value.sub(target_collateral_value);
            _exceeded = true;
        } else {
            _collateral_value = target_collateral_value.sub(total_collateral_value);
            _exceeded = false;
        }
    }

    function get10SHAREPrice() public view returns (uint _10SHAREPrice) {
        try IOracle(_10SHAREOracle).consult(_10SHARE, PRICE_PRECISION) returns (uint144 price) {
            return uint(price);
        } catch {
            revert("Treasury: failed to consult 10SHARE price from the oracle");
        }
    }

    // oracle
    function getArbiTenPrice() public view returns (uint ArbiTenPrice) {
        try IOracle(ArbiTenOracle).consult(ArbiTen, PRICE_PRECISION) returns (uint144 price) {
            return uint(price);
        } catch {
            revert("Treasury: failed to consult ArbiTen price from the oracle");
        }
    }

    function getArbiTenUpdatedPrice() public view returns (uint _ArbiTenPrice) {
        try IOracle(ArbiTenOracle).twap(ArbiTen, PRICE_PRECISION) returns (uint144 price) {
            return uint(price);
        } catch {
            revert("Treasury: failed to consult ArbiTen price from the oracle");
        }
    }

    // budget
    function getReserve() public view returns (uint) {
        return seigniorageSaved;
    }

    function getBurnableArbiTenLeft() public view returns (uint _burnableArbiTenLeft) {
        uint _ArbiTenPrice = getArbiTenPrice();
        if (_ArbiTenPrice <= ArbiTenPriceOne) {
            uint _ArbiTenSupply = getArbiTenCirculatingSupply();
            uint _bondMaxSupply = _ArbiTenSupply.mul(maxDebtRatioPercent).div(10000);
            uint _bondSupply = IERC20(_10BOND).totalSupply();
            if (_bondMaxSupply > _bondSupply) {
                uint _maxMintableBond = _bondMaxSupply.sub(_bondSupply);
                uint _rate = getBondDiscountRate();
                if (_rate > 0) {
                    uint _maxBurnableArbiTen = _maxMintableBond.mul(ArbiTenPriceOne).div(_rate);
                    _burnableArbiTenLeft = Math.min(epochSupplyContractionLeft, _maxBurnableArbiTen);
                }
            }
        }
    }

    function getRedeemableBonds() public view returns (uint _redeemableBonds) {
        uint _ArbiTenPrice = getArbiTenPrice();
        if (_ArbiTenPrice > ArbiTenPriceCeiling) {
            uint _totalArbiTen = IERC20(ArbiTen).balanceOf(address(this));
            uint _rate = getBondPremiumRate();
            if (_rate > 0) {
                _redeemableBonds = _totalArbiTen.mul(ArbiTenPriceOne).div(_rate);
            }
        }
    }

    function getBondDiscountRate() public view returns (uint _rate) {
        uint _ArbiTenPrice = getArbiTenPrice();
        if (_ArbiTenPrice <= ArbiTenPriceOne) {
            if (discountPercent == 0) {
                // no discount
                _rate = ArbiTenPriceOne;
            } else {
                uint _bondAmount = ArbiTenPriceOne.mul(ArbiTenPriceOne).div(_ArbiTenPrice); // to burn 1 ArbiTen
                uint _discountAmount = _bondAmount.sub(ArbiTenPriceOne).mul(discountPercent).div(10000);
                _rate = ArbiTenPriceOne.add(_discountAmount);
                if (maxDiscountRate > 0 && _rate > maxDiscountRate) {
                    _rate = maxDiscountRate;
                }
            }
        }
    }

    function getBondPremiumRate() public view returns (uint _rate) {
        uint _ArbiTenPrice = getArbiTenPrice();
        if (_ArbiTenPrice > ArbiTenPriceCeiling) {
            uint _ArbiTenPricePremiumThreshold = ArbiTenPriceOne.mul(premiumThreshold).div(100);
            if (_ArbiTenPrice >= _ArbiTenPricePremiumThreshold) {
                //Price > 1.01
                uint _premiumAmount =  _ArbiTenPrice.sub(ArbiTenPriceOne).mul(premiumPercent).div(10000);
                _rate = ArbiTenPriceOne.add(_premiumAmount);
                if (maxPremiumRate > 0 && _rate > maxPremiumRate) {
                    _rate = maxPremiumRate;
                }
            } else {
                // no premium bonus
                _rate = ArbiTenPriceOne;
            }
        }
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _ArbiTen,
        address __10BOND,
        address __10SHARE,
        address _ArbiTenOracle,
        address __10SHAREOracle,
        address _boardroom,
        uint _startTime
    ) public notInitialized onlyOperator {
        ArbiTen = _ArbiTen;
        _10BOND = __10BOND;
        _10SHARE = __10SHARE;
        ArbiTenOracle = _ArbiTenOracle;
        _10SHAREOracle = __10SHAREOracle;
        boardroom = _boardroom;
        startTime = _startTime;

        ArbiTenPriceOne = PRICE_PRECISION.div(10);
        ArbiTenPriceCeiling = ArbiTenPriceOne.mul(101).div(100);

        ArbiTenSupplyTarget = 1000000 ether;

        maxSupplyExpansionPercent = 100; // Upto 1.00% supply for expansion
        minMaxSupplyExpansionPercent = 10; // Minimum max of 0.1% supply for expansion


        boardroomWithdrawFee = 2; // 2% withdraw fee when under peg

        bondDepletionFloorPercent = 10000; // 100% of Bond supply for depletion floor
        seigniorageExpansionFloorPercent = 3500; // At least 35% of expansion reserved for boardroom
        maxSupplyContractionPercent = 300; // Upto 3.0% supply for contraction (to burn ArbiTen and mint 10BOND)
        maxDebtRatioPercent = 3500; // Upto 35% supply of 10BOND to purchase

        premiumThreshold = 101;
        premiumPercent = 5000;

        // First 24 epochs with 4.5% expansion
        bootstrapEpochs = 24;
        bootstrapSupplyExpansionPercent = 110;

        // set seigniorageSaved to it's balance
        seigniorageSaved = IERC20(ArbiTen).balanceOf(address(this));

        initialized = true;

        // iron initialization
        ratio_step = 2500; // = 0.25% at 6 decimals of precision
        target_collateral_ratio = 1000000; // = 100% - fully collateralized at start
        effective_collateral_ratio = 1000000; // = 100% - fully collateralized at start
        refresh_cooldown = 3600; // Refresh cooldown period is set to 1 hour (3600 seconds) at genesis
        price_target = ArbiTenPriceOne; // = $0.1. (18 decimals of precision). Collateral ratio will adjust according to the $0.1 price target at genesis
        price_band = 500;
        redemption_fee = 4000;
        minting_fee = 4000;

        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setBoardroom(address _boardroom) external onlyOperator {
        boardroom = _boardroom;
    }

    function setBoardroomWithdrawFee(uint _boardroomWithdrawFee) external onlyOperator {
        require(_boardroomWithdrawFee <= 20, "Max withdraw fee is 20%");
        boardroomWithdrawFee = _boardroomWithdrawFee;
    }

    function setBoardroomStakeFee(uint _boardroomStakeFee) external onlyOperator {
        require(_boardroomStakeFee <= 5, "Max stake fee is 5%");
        boardroomStakeFee = _boardroomStakeFee;
        IBoardroom(boardroom).setStakeFee(boardroomStakeFee);
    }

    function setArbiTenOracle(address _ArbiTenOracle) external onlyOperator {
        ArbiTenOracle = _ArbiTenOracle;
    }

    function setArbiTenPriceCeiling(uint _ArbiTenPriceCeiling) external onlyOperator {
        require(_ArbiTenPriceCeiling >= ArbiTenPriceOne && _ArbiTenPriceCeiling <= ArbiTenPriceOne.mul(120).div(100), "out of range"); // [$0.1, $0.12]
        ArbiTenPriceCeiling = _ArbiTenPriceCeiling;
    }

    function setMinMaxSupplyExpansionPercent(uint _minMaxSupplyExpansionPercent) external onlyOperator {
        require(_minMaxSupplyExpansionPercent <= 100, "_minMaxSupplyExpansionPercent: out of range"); // [0%, 1%]
        minMaxSupplyExpansionPercent = _minMaxSupplyExpansionPercent;
    }

    function setMaxSupplyExpansionPercent(uint _maxSupplyExpansionPercent) external onlyOperator {
        require(_maxSupplyExpansionPercent >= minMaxSupplyExpansionPercent && _maxSupplyExpansionPercent <= 1000, "_maxSupplyExpansionPercent: out of range"); // [minMax%, 10%]
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
    }

    function setBondDepletionFloorPercent(uint _bondDepletionFloorPercent) external onlyOperator {
        require(_bondDepletionFloorPercent >= 500 && _bondDepletionFloorPercent <= 10000, "out of range"); // [5%, 100%]
        bondDepletionFloorPercent = _bondDepletionFloorPercent;
    }

    function setMaxSupplyContractionPercent(uint _maxSupplyContractionPercent) external onlyOperator {
        require(_maxSupplyContractionPercent >= 100 && _maxSupplyContractionPercent <= 1500, "out of range"); // [0.1%, 15%]
        maxSupplyContractionPercent = _maxSupplyContractionPercent;
    }

    function setMaxDebtRatioPercent(uint _maxDebtRatioPercent) external onlyOperator {
        require(_maxDebtRatioPercent >= 1000 && _maxDebtRatioPercent <= 10000, "out of range"); // [10%, 100%]
        maxDebtRatioPercent = _maxDebtRatioPercent;
    }

    function setBootstrap(uint _bootstrapEpochs, uint _bootstrapSupplyExpansionPercent) external onlyOperator {
        require(_bootstrapEpochs <= 90, "_bootstrapEpochs: out of range"); // <= 1 month
        require(_bootstrapSupplyExpansionPercent >= 100 && _bootstrapSupplyExpansionPercent <= 1000, "_bootstrapSupplyExpansionPercent: out of range"); // [1%, 10%]
        bootstrapEpochs = _bootstrapEpochs;
        bootstrapSupplyExpansionPercent = _bootstrapSupplyExpansionPercent;
    }

    function setExtraFunds(
        address _daoFund,
        uint _daoFundSharedPercent,
        address _devFund,
        uint _devFundSharedPercent,
        address _insuranceFund,
        uint _insuranceFundSharedPercent,
        address _equityFund,
        uint _equityFundSharedPercent
    ) external onlyOperator {
        require(_daoFund != address(0), "zero");
        require(_daoFundSharedPercent <= 5000, "out of range"); // <= 50%
        require(_devFund != address(0), "zero");
        require(_devFundSharedPercent <= 5000, "out of range"); // <= 10%
        require(_insuranceFund != address(0), "zero");
        require(_insuranceFundSharedPercent <= 5000, "out of range"); // <= 50%
        require(_equityFund != address(0), "zero");
        require(_equityFundSharedPercent <= 5000, "out of range"); // <= 50%

        daoFund = _daoFund;
        daoFundSharedPercent = _daoFundSharedPercent;

        devFund = _devFund;
        devFundSharedPercent = _devFundSharedPercent;

        insuranceFund = _insuranceFund;
        insuranceFundSharedPercent = _insuranceFundSharedPercent;

        equityFund = _equityFund;
        equityFundSharedPercent = _equityFundSharedPercent;
    }

    function setMaxDiscountRate(uint _maxDiscountRate) external onlyOperator {
        maxDiscountRate = _maxDiscountRate;
    }

    function setMaxPremiumRate(uint _maxPremiumRate) external onlyOperator {
        maxPremiumRate = _maxPremiumRate;
    }

    function setDiscountPercent(uint _discountPercent) external onlyOperator {
        require(_discountPercent <= 20000, "_discountPercent is over 200%");
        discountPercent = _discountPercent;
    }

    function setPremiumThreshold(uint _premiumThreshold) external onlyOperator {
        require(_premiumThreshold >= ArbiTenPriceCeiling, "_premiumThreshold exceeds ArbiTenPriceCeiling");
        require(_premiumThreshold <= 150, "_premiumThreshold is higher than 1.5");
        premiumThreshold = _premiumThreshold;
    }

    function setPremiumPercent(uint _premiumPercent) external onlyOperator {
        require(_premiumPercent <= 20000, "_premiumPercent is over 200%");
        premiumPercent = _premiumPercent;
    }

    function setMintingFactorForPayingDebt(uint _mintingFactorForPayingDebt) external onlyOperator {
        require(_mintingFactorForPayingDebt >= 10000 && _mintingFactorForPayingDebt <= 20000, "_mintingFactorForPayingDebt: out of range"); // [100%, 200%]
        mintingFactorForPayingDebt = _mintingFactorForPayingDebt;
    }

    function setArbiTenSupplyTarget(uint _ArbiTenSupplyTarget) external onlyOperator {
        require(_ArbiTenSupplyTarget > getArbiTenCirculatingSupply(), "too small"); // >= current circulating supply
        ArbiTenSupplyTarget = _ArbiTenSupplyTarget;
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    // Add new Pool
    function addPool(address pool_address) public onlyOperator {
        require(pools[pool_address] == false, "poolExisted");
        pools[pool_address] = true;
        pools_array.push(pool_address);
    }

    // Remove a pool
    function removePool(address pool_address) public onlyOperator {
        require(pools[pool_address] == true, "!pool");
        // Delete from the mapping
        delete pools[pool_address];
        // 'Delete' from the array by setting the address to 0x0
        for (uint i = 0; i < pools_array.length; i++) {
            if (pools_array[i] == pool_address) {
                pools_array[i] = address(0); // This will leave a null in the array and keep the indices the same
                break;
            }
        }
    }

    function _updateArbiTenPrice() internal {
        try IOracle(ArbiTenOracle).update() {} catch {}
    }

    function _update10SHAREPrice() internal {
        try IOracle(_10SHAREOracle).update() {} catch {}
    }

    function getArbiTenCirculatingSupply() public view returns (uint) {
        IERC20 ArbiTenErc20 = IERC20(ArbiTen);
        uint totalSupply = ArbiTenErc20.totalSupply();
        uint balanceExcluded = 0;
        for (uint8 entryId = 0; entryId < excludedFromTotalSupply.length; ++entryId) {
            balanceExcluded = balanceExcluded.add(ArbiTenErc20.balanceOf(excludedFromTotalSupply[entryId]));
        }
        uint totalCircSupply =  totalSupply.sub(balanceExcluded);
        uint totalIronSupply = globalIronSupply();
        if (totalCircSupply > totalIronSupply)
            return totalCircSupply.sub(totalIronSupply);
        return 0;
    }

    function buyBonds(uint _ArbiTenAmount, uint targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_ArbiTenAmount > 0, "Treasury: cannot purchase bonds with zero amount");

        uint ArbiTenPrice = getArbiTenPrice();
        require(ArbiTenPrice == targetPrice, "Treasury: ArbiTen price moved");
        require(
            ArbiTenPrice < ArbiTenPriceOne, // price < $0.1
            "Treasury: ArbiTenPrice not eligible for bond purchase"
        );

        require(_ArbiTenAmount <= epochSupplyContractionLeft, "Treasury: not enough bond left to purchase");

        uint _rate = getBondDiscountRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint _bondAmount = _ArbiTenAmount.mul(_rate).div(ArbiTenPriceOne);
        uint ArbiTenSupply = getArbiTenCirculatingSupply();
        uint newBondSupply = IERC20(_10BOND).totalSupply().add(_bondAmount);
        require(newBondSupply <= ArbiTenSupply.mul(maxDebtRatioPercent).div(10000), "over max debt ratio");

        IBasisAsset(ArbiTen).burnFrom(msg.sender, _ArbiTenAmount);
        IBasisAsset(_10BOND).mint(msg.sender, _bondAmount);

        epochSupplyContractionLeft = epochSupplyContractionLeft.sub(_ArbiTenAmount);
        
        //_updateArbiTenPrice();
        treasuryUpdates();

        emit BoughtBonds(msg.sender, _ArbiTenAmount, _bondAmount);
    }

    function redeemBonds(uint _bondAmount, uint targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_bondAmount > 0, "Treasury: cannot redeem bonds with zero amount");

        uint ArbiTenPrice = getArbiTenPrice();
        require(ArbiTenPrice == targetPrice, "Treasury: ArbiTen price moved");
        require(
            ArbiTenPrice > ArbiTenPriceCeiling, // price > $1.01
            "Treasury: ArbiTenPrice not eligible for bond purchase"
        );

        uint _rate = getBondPremiumRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint _ArbiTenAmount = _bondAmount.mul(_rate).div(ArbiTenPriceOne);
        require(IERC20(ArbiTen).balanceOf(address(this)) >= _ArbiTenAmount, "Treasury: treasury has no more budget");

        seigniorageSaved = seigniorageSaved.sub(Math.min(seigniorageSaved, _ArbiTenAmount));

        IBasisAsset(_10BOND).burnFrom(msg.sender, _bondAmount);
        IERC20(ArbiTen).safeTransfer(msg.sender, _ArbiTenAmount);

        //_updateArbiTenPrice();
        treasuryUpdates();

        emit RedeemedBonds(msg.sender, _ArbiTenAmount, _bondAmount);
    }

    function _sendToBoardroom(uint _amount) internal {
        IBasisAsset(ArbiTen).mint(address(this), _amount);

        uint _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(10000);
            IERC20(ArbiTen).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(block.timestamp, _daoFundSharedAmount);
        }

        uint _devFundSharedAmount = 0;
        if (devFundSharedPercent > 0) {
            _devFundSharedAmount = _amount.mul(devFundSharedPercent).div(10000);
            IERC20(ArbiTen).transfer(devFund, _devFundSharedAmount);
            emit DevFundFunded(block.timestamp, _devFundSharedAmount);
        }

        uint _insuranceFundSharedAmount = 0;
        if (insuranceFundSharedPercent > 0) {
            _insuranceFundSharedAmount = _amount.mul(insuranceFundSharedPercent).div(10000);
            IERC20(ArbiTen).transfer(insuranceFund, _insuranceFundSharedAmount);
            emit InsuranceFundFunded(block.timestamp, _insuranceFundSharedAmount);
        }

        uint _equityFundSharedAmount = 0;
        if (equityFundSharedPercent > 0) {
            _equityFundSharedAmount = _amount.mul(equityFundSharedPercent).div(10000);
            IERC20(ArbiTen).transfer(equityFund, _equityFundSharedAmount);
            emit EquityFundFunded(block.timestamp, _equityFundSharedAmount);
        }

        _amount = _amount.sub(_daoFundSharedAmount).sub(_devFundSharedAmount)
                            .sub(_insuranceFundSharedAmount).sub(_equityFundSharedAmount);

        IERC20(ArbiTen).safeApprove(boardroom, 0);
        IERC20(ArbiTen).safeApprove(boardroom, _amount);

        IBoardroom(boardroom).allocateSeigniorage(_amount);

        emit BoardroomFunded(block.timestamp, _amount);
    }

    function _calculateMaxSupplyExpansionPercent(uint _ArbiTenSupply) internal returns (uint) {
        if (_ArbiTenSupply >= ArbiTenSupplyTarget) {
            ArbiTenSupplyTarget = ArbiTenSupplyTarget.mul(12500).div(10000); // +25%
            maxSupplyExpansionPercent = maxSupplyExpansionPercent.mul(9500).div(10000); // -5%
            if (maxSupplyExpansionPercent < minMaxSupplyExpansionPercent) {
                maxSupplyExpansionPercent = minMaxSupplyExpansionPercent; // min 0.1% by default
            }
        }
        return maxSupplyExpansionPercent;
    }

    function getArbiTenExpansionRate() public view returns (uint _rate) {
        if (epoch < bootstrapEpochs) { // 24 first epochs with 3.5% expansion
            _rate = bootstrapSupplyExpansionPercent;
        } else {
            uint _twap = getArbiTenPrice();
            if (_twap >= ArbiTenPriceCeiling) {
                uint _percentage = _twap.sub(ArbiTenPriceOne); // 1% = 1e3
                uint _mse = maxSupplyExpansionPercent.mul(1e13);
                if (_percentage > _mse) {
                    _percentage = _mse;
                }
                _rate = _percentage.div(1e13);
            }
        }
    }

    function getArbiTenExpansionAmount() external view returns (uint) {
        uint ArbiTenSupply = getArbiTenCirculatingSupply().sub(seigniorageSaved);
        uint bondSupply = IERC20(_10BOND).totalSupply();
        uint _rate = getArbiTenExpansionRate();
        if (seigniorageSaved >= bondSupply.mul(bondDepletionFloorPercent).div(10000)) {
            // saved enough to pay debt, mint as usual rate
            return ArbiTenSupply.mul(_rate).div(10000);
        } else {
            // have not saved enough to pay debt, mint more
            uint _seigniorage = ArbiTenSupply.mul(_rate).div(10000);
            return _seigniorage.mul(seigniorageExpansionFloorPercent).div(10000);
        }
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        require(IBoardroom(boardroom).totalSupply() > 0, "cannot update if boardroom total supply is 0");
        _updateArbiTenPrice();
        _update10SHAREPrice();

        previousEpochArbiTenPrice = getArbiTenPrice();
        uint ArbiTenSupply = getArbiTenCirculatingSupply().sub(seigniorageSaved);
        if (epoch < bootstrapEpochs) {
            // 21 first epochs with 3.5% expansion
            _sendToBoardroom(ArbiTenSupply.mul(bootstrapSupplyExpansionPercent).div(10000));
            emit Seigniorage(epoch, previousEpochArbiTenPrice, ArbiTenSupply.mul(bootstrapSupplyExpansionPercent).div(10000));
        } else {
            if (previousEpochArbiTenPrice >= ArbiTenPriceCeiling) {
                IBoardroom(boardroom).setWithdrawFee(0);
                // Expansion ($ArbiTen Price > 0.1 $eth): there is some seigniorage to be allocated
                uint bondSupply = IERC20(_10BOND).totalSupply();
                uint _percentage = previousEpochArbiTenPrice.sub(ArbiTenPriceOne);
                uint _savedForBond;
                uint _savedForBoardroom;
                uint _mse = _calculateMaxSupplyExpansionPercent(ArbiTenSupply).mul(1e13);
                if (_percentage > _mse) {
                    _percentage = _mse;
                }
                if (seigniorageSaved >= bondSupply.mul(bondDepletionFloorPercent).div(10000)) {
                    // saved enough to pay debt, mint as usual rate
                    _savedForBoardroom = ArbiTenSupply.mul(_percentage).div(ArbiTenPriceOne);
                } else {
                    // have not saved enough to pay debt, mint more
                    uint _seigniorage = ArbiTenSupply.mul(_percentage).div(ArbiTenPriceOne);
                    _savedForBoardroom = _seigniorage.mul(seigniorageExpansionFloorPercent).div(10000);
                    _savedForBond = _seigniorage.sub(_savedForBoardroom);
                    if (mintingFactorForPayingDebt > 0) {
                        _savedForBond = _savedForBond.mul(mintingFactorForPayingDebt).div(10000);
                    }
                }
                if (_savedForBoardroom > 0) {
                    _sendToBoardroom(_savedForBoardroom);
                }
                if (_savedForBond > 0) {
                    seigniorageSaved = seigniorageSaved.add(_savedForBond);
                    IBasisAsset(ArbiTen).mint(address(this), _savedForBond);
                    emit TreasuryFunded(block.timestamp, _savedForBond);
                }
                emit Seigniorage(epoch, previousEpochArbiTenPrice, _savedForBoardroom);
            } else {
                IBoardroom(boardroom).setWithdrawFee(boardroomWithdrawFee);
                emit Seigniorage(epoch, previousEpochArbiTenPrice, 0);
            }
        }
    }

    function treasuryUpdates() public {
        bool hasReverted = false;

        try this.allocateSeigniorage() {} catch {
            hasReverted = true;
        }
        if (hasReverted) {
            _updateArbiTenPrice();
            _update10SHAREPrice();
        }

        try this.refreshCollateralRatio() {} catch {}
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint _amount,
        address _to
    ) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(ArbiTen), "ArbiTen");
        require(address(_token) != address(_10BOND), "_10BOND");
        require(address(_token) != address(_10SHARE), "share");
        _token.safeTransfer(_to, _amount);
    }

    function boardroomSetOperator(address _operator) external onlyOperator {
        IBoardroom(boardroom).setOperator(_operator);
    }

    function boardroomSetReserveFund(address _reserveFund) external onlyOperator {
        IBoardroom(boardroom).setReserveFund(_reserveFund);
    }

    function boardroomSetLockUp(uint _withdrawLockupEpochs, uint _rewardLockupEpochs) external onlyOperator {
        IBoardroom(boardroom).setLockUp(_withdrawLockupEpochs, _rewardLockupEpochs);
    }

    function boardroomAllocateSeigniorage(uint amount) external onlyOperator {
        IERC20(ArbiTen).safeApprove(boardroom, amount);
        IBoardroom(boardroom).allocateSeigniorage(amount);
    }

    function boardroomGovernanceRecoverUnsupported(
        address _token,
        uint _amount,
        address _to
    ) external onlyOperator {
        IBoardroom(boardroom).governanceRecoverUnsupported(_token, _amount, _to);
    }

    function hasPool(address _address) external view returns (bool) {
        return pools[_address] == true;
    }

    function setRedemptionFee(uint _redemption_fee) public onlyOperator {
        require(_redemption_fee < 100000, "redemption fee too high");
        redemption_fee = _redemption_fee;
    }

    function setMintingFee(uint _minting_fee) public onlyOperator {
        require(_minting_fee < 100000, "minting fee too high");
        minting_fee = _minting_fee;
    }

    function setRatioStep(uint _ratio_step) public onlyOperator {
        ratio_step = _ratio_step;
    }

    function setPriceTarget(uint _price_target) public onlyOperator {
        price_target = _price_target;
    }

    function setRefreshCooldown(uint _refresh_cooldown) public onlyOperator {
        refresh_cooldown = _refresh_cooldown;
    }

    function setPriceBand(uint _price_band) external onlyOperator {
        price_band = _price_band;
    }

    function toggleCollateralRatio() public onlyOperator {
        collateral_ratio_paused = !collateral_ratio_paused;
    }

    function toggleEffectiveCollateralRatio() public onlyOperator {
        using_effective_collateral_ratio = !using_effective_collateral_ratio;
    }


    /* ========== EMERGENCY ========== */

    function executeTransaction(
        address target,
        uint value,
        string memory signature,
        bytes memory data
    ) public onlyOperator returns (bytes memory) {
        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }
        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(success, string("Treasury::executeTransaction: Transaction execution reverted."));
        emit TransactionExecuted(target, value, signature, data);
        return returnData;
    }
}

