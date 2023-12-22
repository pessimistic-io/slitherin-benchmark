// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow, so we distribute
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
    }
}

contract Operator is Context, Ownable {
    address private _operator;

    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);

    constructor() {
        _operator = _msgSender();
        emit OperatorTransferred(address(0), _operator);
    }

    function operator() public view returns (address) {
        return _operator;
    }

    modifier onlyOperator() {
        require(_operator == msg.sender, "operator: caller is not the operator");
        _;
    }

    function isOperator() public view returns (bool) {
        return _msgSender() == _operator;
    }

    function transferOperator(address newOperator_) public onlyOwner {
        _transferOperator(newOperator_);
    }

    function _transferOperator(address newOperator_) internal {
        require(newOperator_ != address(0), "operator: zero address given for new operator");
        emit OperatorTransferred(address(0), newOperator_);
        _operator = newOperator_;
    }
}

contract ContractGuard {
    mapping(uint256 => mapping(address => bool)) private _status;

    function checkSameOriginReentranted() internal view returns (bool) {
        return _status[block.number][tx.origin];
    }

    function checkSameSenderReentranted() internal view returns (bool) {
        return _status[block.number][msg.sender];
    }

    modifier onlyOneBlock() {
        require(!checkSameOriginReentranted(), "ContractGuard: one block, one function");
        require(!checkSameSenderReentranted(), "ContractGuard: one block, one function");

        _;

        _status[block.number][tx.origin] = true;
        _status[block.number][msg.sender] = true;
    }
}

library Babylonian {
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
        // else z = 0
    }
}

interface IOracle {
    function update() external;
    function consult(address _token, uint256 _amountIn) external view returns (uint144 amountOut);
    function twap(address _token, uint256 _amountIn) external view returns (uint144 _amountOut);
}

interface IBoardroom {
    function balanceOf(address _board) external view returns (uint256);

    function earned(address _board) external view returns (uint256);

    function canWithdraw(address _board) external view returns (bool);

    function canClaimReward(address _board) external view returns (bool);

    function epoch() external view returns (uint256);

    function nextEpochPoint() external view returns (uint256);

    function getHopePrice() external view returns (uint256);

    function setOperator(address _operator) external;

    function setLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external;

    function stake(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function exit() external;

    function claimReward() external;

    function allocateSeigniorage(uint256 _amount) external;

    function governanceRecoverUnsupported(address _token, uint256 _amount, address _to) external;
}

interface IBasisAsset {
    function mint(address recipient, uint256 amount) external returns (bool);

    function burn(uint256 amount) external;

    function burnFrom(address from, uint256 amount) external;

    function isOperator() external returns (bool);

    function operator() external view returns (address);

    function transferOperator(address newOperator_) external;
}

contract Treasury is ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========= CONSTANT VARIABLES ======== */

    uint256 public constant PERIOD = 6 hours;

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;

    // flags
    bool public initialized = false;

    // epoch
    uint256 public startTime;
    uint256 public epoch = 0;
    uint256 public epochSupplyContractionLeft = 0;

    // exclusions from total supply
    address[] public excludedFromTotalSupply = [
        address(0x95bCc720EC902012fFB02b7E0Aea30209D2C6e3B) // HopeGenesisPool
    ];

    // core components
    address public hope;
    address public wish;
    address public dream;

    address public boardroom;
    address public hopeOracle;

    // price
    uint256 public hopePriceOne;
    uint256 public hopePriceCeiling;

    uint256 public seigniorageSaved;

    uint256[] public supplyTiers;
    uint256[] public maxExpansionTiers;

    uint256 public maxSupplyExpansionPercent;
    uint256 public bondDepletionFloorPercent;
    uint256 public seigniorageExpansionFloorPercent;
    uint256 public maxSupplyContractionPercent;
    uint256 public maxDebtRatioPercent;

    // 28 first epochs (1 week) with 4.5% expansion regardless of HOPE price
    uint256 public bootstrapEpochs;
    uint256 public bootstrapSupplyExpansionPercent;

    /* =================== Added variables =================== */
    uint256 public previousEpochHopePrice;
    uint256 public maxDiscountRate; // when purchasing bond
    uint256 public maxPremiumRate; // when redeeming bond
    uint256 public discountPercent;
    uint256 public premiumThreshold;
    uint256 public premiumPercent;
    uint256 public mintingFactorForPayingDebt; // print extra HOPE during debt phase

    address public daoFund;
    uint256 public daoFundSharedPercent;

    address public devFund;
    uint256 public devFundSharedPercent;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event BurnedBonds(address indexed from, uint256 bondAmount);
    event RedeemedBonds(address indexed from, uint256 hopeAmount, uint256 bondAmount);
    event BoughtBonds(address indexed from, uint256 hopeAmount, uint256 bondAmount);
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event BoardroomFunded(uint256 timestamp, uint256 seigniorage);
    event DaoFundFunded(uint256 timestamp, uint256 seigniorage);
    event DevFundFunded(uint256 timestamp, uint256 seigniorage);

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
        epochSupplyContractionLeft = (getHopePrice() > hopePriceCeiling) ? 0 : getHopeCirculatingSupply().mul(maxSupplyContractionPercent).div(10000);
    }

    modifier checkOperator {
        require(
            IBasisAsset(hope).operator() == address(this) &&
                IBasisAsset(wish).operator() == address(this) &&
                IBasisAsset(dream).operator() == address(this) &&
                Operator(boardroom).operator() == address(this),
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
    function nextEpochPoint() public view returns (uint256) {
        return startTime.add(epoch.mul(PERIOD));
    }

    // oracle
    function getHopePrice() public view returns (uint256 hopePrice) {
        try IOracle(hopeOracle).consult(hope, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult HOPE price from the oracle");
        }
    }

    function getHopeUpdatedPrice() public view returns (uint256 _hopePrice) {
        try IOracle(hopeOracle).twap(hope, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult HOPE price from the oracle");
        }
    }

    // budget
    function getReserve() public view returns (uint256) {
        return seigniorageSaved;
    }

    function getBurnableHopeLeft() public view returns (uint256 _burnableHopeLeft) {
        uint256 _hopePrice = getHopePrice();
        if (_hopePrice <= hopePriceOne) {
            uint256 _hopeSupply = getHopeCirculatingSupply();
            uint256 _bondMaxSupply = _hopeSupply.mul(maxDebtRatioPercent).div(10000);
            uint256 _bondSupply = IERC20(wish).totalSupply();
            if (_bondMaxSupply > _bondSupply) {
                uint256 _maxMintableBond = _bondMaxSupply.sub(_bondSupply);
                uint256 _maxBurnableHope = _maxMintableBond.mul(_hopePrice).div(1e18);
                _burnableHopeLeft = Math.min(epochSupplyContractionLeft, _maxBurnableHope);
            }
        }
    }

    function getRedeemableBonds() public view returns (uint256 _redeemableBonds) {
        uint256 _hopePrice = getHopePrice();
        if (_hopePrice > hopePriceCeiling) {
            uint256 _totalHope = IERC20(hope).balanceOf(address(this));
            uint256 _rate = getBondPremiumRate();
            if (_rate > 0) {
                _redeemableBonds = _totalHope.mul(1e18).div(_rate);
            }
        }
    }

    function getBondDiscountRate() public view returns (uint256 _rate) {
        uint256 _hopePrice = getHopePrice();
        if (_hopePrice <= hopePriceOne) {
            if (discountPercent == 0) {
                // no discount
                _rate = hopePriceOne;
            } else {
                uint256 _bondAmount = hopePriceOne.mul(1e18).div(_hopePrice); // to burn 1 HOPE
                uint256 _discountAmount = _bondAmount.sub(hopePriceOne).mul(discountPercent).div(10000);
                _rate = hopePriceOne.add(_discountAmount);
                if (maxDiscountRate > 0 && _rate > maxDiscountRate) {
                    _rate = maxDiscountRate;
                }
            }
        }
    }

    function getBondPremiumRate() public view returns (uint256 _rate) {
        uint256 _hopePrice = getHopePrice();
        if (_hopePrice > hopePriceCeiling) {
            uint256 _hopePricePremiumThreshold = hopePriceOne.mul(premiumThreshold).div(100);
            if (_hopePrice >= _hopePricePremiumThreshold) {
                //Price > 1.10
                uint256 _premiumAmount = _hopePrice.sub(hopePriceOne).mul(premiumPercent).div(10000);
                _rate = hopePriceOne.add(_premiumAmount);
                if (maxPremiumRate > 0 && _rate > maxPremiumRate) {
                    _rate = maxPremiumRate;
                }
            } else {
                // no premium bonus
                _rate = hopePriceOne;
            }
        }
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _hope,
        address _wish,
        address _dream,
        address _hopeOracle,
        address _boardroom,
        uint256 _startTime
    ) public notInitialized {
        hope = _hope;
        wish = _wish;
        dream = _dream;
        hopeOracle = _hopeOracle;
        boardroom = _boardroom;
        startTime = _startTime;

        hopePriceOne = 10**15;
        hopePriceCeiling = hopePriceOne.mul(101).div(100);

        // Dynamic max expansion percent
        supplyTiers = [0 ether, 500000 ether, 1000000 ether, 1500000 ether, 2000000 ether, 5000000 ether, 10000000 ether, 20000000 ether, 50000000 ether];
        maxExpansionTiers = [450, 400, 350, 300, 250, 200, 150, 125, 100];

        maxSupplyExpansionPercent = 400; // Upto 4.0% supply for expansion

        bondDepletionFloorPercent = 10000; // 100% of Bond supply for depletion floor
        seigniorageExpansionFloorPercent = 3500; // At least 35% of expansion reserved for boardroom
        maxSupplyContractionPercent = 300; // Upto 3.0% supply for contraction (to burn HOPE and mint gBOND)
        maxDebtRatioPercent = 3500; // Upto 35% supply of gBOND to purchase

        premiumThreshold = 110;
        premiumPercent = 7000;

        // First 28 epochs with 4.5% expansion
        bootstrapEpochs = 28;
        bootstrapSupplyExpansionPercent = 450;

        // set seigniorageSaved to it's balance
        seigniorageSaved = IERC20(hope).balanceOf(address(this));

        initialized = true;
        operator = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setBoardroom(address _boardroom) external onlyOperator {
        boardroom = _boardroom;
    }

    function sethopeOracle(address _hopeOracle) external onlyOperator {
        hopeOracle = _hopeOracle;
    }

    function sethopePriceCeiling(uint256 _hopePriceCeiling) external onlyOperator {
        require(_hopePriceCeiling >= hopePriceOne && _hopePriceCeiling <= hopePriceOne.mul(120).div(100), "out of range"); // [$1.0, $1.2]
        hopePriceCeiling = _hopePriceCeiling;
    }

    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent) external onlyOperator {
        require(_maxSupplyExpansionPercent >= 10 && _maxSupplyExpansionPercent <= 1000, "_maxSupplyExpansionPercent: out of range"); // [0.1%, 10%]
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
    }

    function setSupplyTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 9, "Index has to be lower than count of tiers");
        if (_index > 0) {
            require(_value > supplyTiers[_index - 1]);
        }
        if (_index < 8) {
            require(_value < supplyTiers[_index + 1]);
        }
        supplyTiers[_index] = _value;
        return true;
    }

    function setMaxExpansionTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 9, "Index has to be lower than count of tiers");
        require(_value >= 10 && _value <= 1000, "_value: out of range"); // [0.1%, 10%]
        maxExpansionTiers[_index] = _value;
        return true;
    }

    function setBondDepletionFloorPercent(uint256 _bondDepletionFloorPercent) external onlyOperator {
        require(_bondDepletionFloorPercent >= 500 && _bondDepletionFloorPercent <= 10000, "out of range"); // [5%, 100%]
        bondDepletionFloorPercent = _bondDepletionFloorPercent;
    }

    function setMaxSupplyContractionPercent(uint256 _maxSupplyContractionPercent) external onlyOperator {
        require(_maxSupplyContractionPercent >= 100 && _maxSupplyContractionPercent <= 1500, "out of range"); // [0.1%, 15%]
        maxSupplyContractionPercent = _maxSupplyContractionPercent;
    }

    function setMaxDebtRatioPercent(uint256 _maxDebtRatioPercent) external onlyOperator {
        require(_maxDebtRatioPercent >= 1000 && _maxDebtRatioPercent <= 10000, "out of range"); // [10%, 100%]
        maxDebtRatioPercent = _maxDebtRatioPercent;
    }

    function setBootstrap(uint256 _bootstrapEpochs, uint256 _bootstrapSupplyExpansionPercent) external onlyOperator {
        require(_bootstrapEpochs <= 120, "_bootstrapEpochs: out of range"); // <= 1 month
        require(_bootstrapSupplyExpansionPercent >= 100 && _bootstrapSupplyExpansionPercent <= 1000, "_bootstrapSupplyExpansionPercent: out of range"); // [1%, 10%]
        bootstrapEpochs = _bootstrapEpochs;
        bootstrapSupplyExpansionPercent = _bootstrapSupplyExpansionPercent;
    }

    function setExtraFunds(
        address _daoFund,
        uint256 _daoFundSharedPercent,
        address _devFund,
        uint256 _devFundSharedPercent
    ) external onlyOperator {
        require(_daoFund != address(0), "zero");
        require(_daoFundSharedPercent <= 3000, "out of range"); // <= 30%
        require(_devFund != address(0), "zero");
        require(_devFundSharedPercent <= 1000, "out of range"); // <= 10%
        daoFund = _daoFund;
        daoFundSharedPercent = _daoFundSharedPercent;
        devFund = _devFund;
        devFundSharedPercent = _devFundSharedPercent;
    }

    function setMaxDiscountRate(uint256 _maxDiscountRate) external onlyOperator {
        maxDiscountRate = _maxDiscountRate;
    }

    function setMaxPremiumRate(uint256 _maxPremiumRate) external onlyOperator {
        maxPremiumRate = _maxPremiumRate;
    }

    function setDiscountPercent(uint256 _discountPercent) external onlyOperator {
        require(_discountPercent <= 20000, "_discountPercent is over 200%");
        discountPercent = _discountPercent;
    }

    function setPremiumThreshold(uint256 _premiumThreshold) external onlyOperator {
        require(_premiumThreshold >= hopePriceCeiling, "_premiumThreshold exceeds hopePriceCeiling");
        require(_premiumThreshold <= 150, "_premiumThreshold is higher than 1.5");
        premiumThreshold = _premiumThreshold;
    }

    function setPremiumPercent(uint256 _premiumPercent) external onlyOperator {
        require(_premiumPercent <= 20000, "_premiumPercent is over 200%");
        premiumPercent = _premiumPercent;
    }

    function setMintingFactorForPayingDebt(uint256 _mintingFactorForPayingDebt) external onlyOperator {
        require(_mintingFactorForPayingDebt >= 10000 && _mintingFactorForPayingDebt <= 20000, "_mintingFactorForPayingDebt: out of range"); // [100%, 200%]
        mintingFactorForPayingDebt = _mintingFactorForPayingDebt;
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    function _updateHopePrice() internal {
        try IOracle(hopeOracle).update() {} catch {}
    }

    function getHopeCirculatingSupply() public view returns (uint256) {
        IERC20 hopeErc20 = IERC20(hope);
        uint256 totalSupply = hopeErc20.totalSupply();
        uint256 balanceExcluded = 0;
        for (uint8 entryId = 0; entryId < excludedFromTotalSupply.length; ++entryId) {
            balanceExcluded = balanceExcluded.add(hopeErc20.balanceOf(excludedFromTotalSupply[entryId]));
        }
        return totalSupply.sub(balanceExcluded);
    }

    function buyBonds(uint256 _hopeAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_hopeAmount > 0, "Treasury: cannot purchase bonds with zero amount");

        uint256 hopePrice = getHopePrice();
        require(hopePrice == targetPrice, "Treasury: HOPE price moved");
        require(
            hopePrice < hopePriceOne, // price < $1
            "Treasury: hopePrice not eligible for bond purchase"
        );

        require(_hopeAmount <= epochSupplyContractionLeft, "Treasury: not enough bond left to purchase");

        uint256 _rate = getBondDiscountRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _bondAmount = _hopeAmount.mul(_rate).div(1e15);
        uint256 hopeSupply = getHopeCirculatingSupply();
        uint256 newBondSupply = IERC20(wish).totalSupply().add(_bondAmount);
        require(newBondSupply <= hopeSupply.mul(maxDebtRatioPercent).div(10000), "over max debt ratio");

        IBasisAsset(hope).burnFrom(msg.sender, _hopeAmount);
        IBasisAsset(wish).mint(msg.sender, _bondAmount);

        epochSupplyContractionLeft = epochSupplyContractionLeft.sub(_hopeAmount);
        _updateHopePrice();

        emit BoughtBonds(msg.sender, _hopeAmount, _bondAmount);
    }

    function redeemBonds(uint256 _bondAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_bondAmount > 0, "Treasury: cannot redeem bonds with zero amount");

        uint256 hopePrice = getHopePrice();
        require(hopePrice == targetPrice, "Treasury: HOPE price moved");
        require(
            hopePrice > hopePriceCeiling, // price > $1.01
            "Treasury: hopePrice not eligible for bond purchase"
        );

        uint256 _rate = getBondPremiumRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _hopeAmount = _bondAmount.mul(_rate).div(1e15);
        require(IERC20(hope).balanceOf(address(this)) >= _hopeAmount, "Treasury: treasury has no more budget");

        seigniorageSaved = seigniorageSaved.sub(Math.min(seigniorageSaved, _hopeAmount));

        IBasisAsset(wish).burnFrom(msg.sender, _bondAmount);
        IERC20(hope).safeTransfer(msg.sender, _hopeAmount);

        _updateHopePrice();

        emit RedeemedBonds(msg.sender, _hopeAmount, _bondAmount);
    }

    function _sendToBoardroom(uint256 _amount) internal {
        IBasisAsset(hope).mint(address(this), _amount);

        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(10000);
            IERC20(hope).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(block.timestamp, _daoFundSharedAmount);
        }

        uint256 _devFundSharedAmount = 0;
        if (devFundSharedPercent > 0) {
            _devFundSharedAmount = _amount.mul(devFundSharedPercent).div(10000);
            IERC20(hope).transfer(devFund, _devFundSharedAmount);
            emit DevFundFunded(block.timestamp, _devFundSharedAmount);
        }

        _amount = _amount.sub(_daoFundSharedAmount).sub(_devFundSharedAmount);

        IERC20(hope).safeApprove(boardroom, 0);
        IERC20(hope).safeApprove(boardroom, _amount);
        IBoardroom(boardroom).allocateSeigniorage(_amount);
        emit BoardroomFunded(block.timestamp, _amount);
    }

    function _calculateMaxSupplyExpansionPercent(uint256 _hopeSupply) internal returns (uint256) {
        for (uint8 tierId = 8; tierId >= 0; --tierId) {
            if (_hopeSupply >= supplyTiers[tierId]) {
                maxSupplyExpansionPercent = maxExpansionTiers[tierId];
                break;
            }
        }
        return maxSupplyExpansionPercent;
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        _updateHopePrice();
        previousEpochHopePrice = getHopePrice();
        uint256 hopeSupply = getHopeCirculatingSupply().sub(seigniorageSaved);
        if (epoch < bootstrapEpochs) {
            // 28 first epochs with 4.5% expansion
            _sendToBoardroom(hopeSupply.mul(bootstrapSupplyExpansionPercent).div(10000));
        } else {
            if (previousEpochHopePrice > hopePriceCeiling) {
                // Expansion ($HOPE Price > 1 $FTM): there is some seigniorage to be allocated
                uint256 bondSupply = IERC20(wish).totalSupply();
                uint256 _percentage = previousEpochHopePrice.sub(hopePriceOne);
                uint256 _savedForBond;
                uint256 _savedForBoardroom;
                uint256 _mse = _calculateMaxSupplyExpansionPercent(hopeSupply).mul(1e14);
                if (_percentage > _mse) {
                    _percentage = _mse;
                }
                if (seigniorageSaved >= bondSupply.mul(bondDepletionFloorPercent).div(10000)) {
                    // saved enough to pay debt, mint as usual rate
                    _savedForBoardroom = hopeSupply.mul(_percentage).div(1e15);
                } else {
                    // have not saved enough to pay debt, mint more
                    uint256 _seigniorage = hopeSupply.mul(_percentage).div(1e15);
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
                    IBasisAsset(hope).mint(address(this), _savedForBond);
                    emit TreasuryFunded(block.timestamp, _savedForBond);
                }
            }
        }
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(hope), "hope");
        require(address(_token) != address(wish), "bond");
        require(address(_token) != address(dream), "dream");
        _token.safeTransfer(_to, _amount);
    }

    function boardroomSetOperator(address _operator) external onlyOperator {
        IBoardroom(boardroom).setOperator(_operator);
    }

    function boardroomSetLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        IBoardroom(boardroom).setLockUp(_withdrawLockupEpochs, _rewardLockupEpochs);
    }

    function boardroomAllocateSeigniorage(uint256 amount) external onlyOperator {
        IBoardroom(boardroom).allocateSeigniorage(amount);
    }

    function boardroomGovernanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IBoardroom(boardroom).governanceRecoverUnsupported(_token, _amount, _to);
    }
}
