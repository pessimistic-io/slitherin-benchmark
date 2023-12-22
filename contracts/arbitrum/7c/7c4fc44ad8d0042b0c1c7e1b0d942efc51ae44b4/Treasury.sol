// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./Math.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Babylonian.sol";
import "./Operator.sol";
import "./ContractGuard.sol";

import "./IERC20.sol";
import "./IBasisAsset.sol";
import "./IOracle.sol";
import "./IBoardroom.sol";

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
        address(0x9b87649B7E25697Fa5586D916695F03fae14D502), // BlobGenesisPool
        address(0x74d2c46C87c4fc9CadE904096C0931E395f912f4) // BlobRewardPool
    ];

    // core components
    address public blob;
    address public crab;
    address public shrimp;

    address public boardroom;
    address public blobOracle;

    // price
    uint256 public blobPriceOne;
    uint256 public blobPriceCeiling;

    uint256 public seigniorageSaved;

    uint256[] public supplyTiers;
    uint256[] public maxExpansionTiers;

    uint256 public maxSupplyExpansionPercent;
    uint256 public bondDepletionFloorPercent;
    uint256 public seigniorageExpansionFloorPercent;
    uint256 public maxSupplyContractionPercent;
    uint256 public maxDebtRatioPercent;

    // 28 first epochs (1 week) with 4.5% expansion regardless of BLOB price
    uint256 public bootstrapEpochs;
    uint256 public bootstrapSupplyExpansionPercent;

    /* =================== Added variables =================== */
    uint256 public previousEpochBlobPrice;
    uint256 public maxDiscountRate; // when purchasing bond
    uint256 public maxPremiumRate; // when redeeming bond
    uint256 public discountPercent;
    uint256 public premiumThreshold;
    uint256 public premiumPercent;
    uint256 public mintingFactorForPayingDebt; // print extra BLOB during debt phase

    address public daoFund;
    uint256 public daoFundSharedPercent;

    address public devFund;
    uint256 public devFundSharedPercent;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event BurnedBonds(address indexed from, uint256 bondAmount);
    event RedeemedBonds(address indexed from, uint256 blobAmount, uint256 bondAmount);
    event BoughtBonds(address indexed from, uint256 blobAmount, uint256 bondAmount);
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
        require(now >= startTime, "Treasury: not started yet");

        _;
    }

    modifier checkEpoch {
        require(now >= nextEpochPoint(), "Treasury: not opened yet");

        _;

        epoch = epoch.add(1);
        epochSupplyContractionLeft = (getBlobPrice() > blobPriceCeiling) ? 0 : getBlobCirculatingSupply().mul(maxSupplyContractionPercent).div(10000);
    }

    modifier checkOperator {
        require(
            IBasisAsset(blob).operator() == address(this) &&
                IBasisAsset(crab).operator() == address(this) &&
                IBasisAsset(shrimp).operator() == address(this) &&
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
    function getBlobPrice() public view returns (uint256 blobPrice) {
        try IOracle(blobOracle).consult(blob, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult BLOB price from the oracle");
        }
    }

    function getBlobUpdatedPrice() public view returns (uint256 _blobPrice) {
        try IOracle(blobOracle).twap(blob, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult BLOB price from the oracle");
        }
    }

    // budget
    function getReserve() public view returns (uint256) {
        return seigniorageSaved;
    }

    function getBurnableBlobLeft() public view returns (uint256 _burnableBlobLeft) {
        uint256 _blobPrice = getBlobPrice();
        if (_blobPrice <= blobPriceOne) {
            uint256 _blobSupply = getBlobCirculatingSupply();
            uint256 _bondMaxSupply = _blobSupply.mul(maxDebtRatioPercent).div(10000);
            uint256 _bondSupply = IERC20(crab).totalSupply();
            if (_bondMaxSupply > _bondSupply) {
                uint256 _maxMintableBond = _bondMaxSupply.sub(_bondSupply);
                uint256 _maxBurnableBlob = _maxMintableBond.mul(_blobPrice).div(1e18);
                _burnableBlobLeft = Math.min(epochSupplyContractionLeft, _maxBurnableBlob);
            }
        }
    }

    function getRedeemableBonds() public view returns (uint256 _redeemableBonds) {
        uint256 _blobPrice = getBlobPrice();
        if (_blobPrice > blobPriceCeiling) {
            uint256 _totalBlob = IERC20(blob).balanceOf(address(this));
            uint256 _rate = getBondPremiumRate();
            if (_rate > 0) {
                _redeemableBonds = _totalBlob.mul(1e18).div(_rate);
            }
        }
    }

    function getBondDiscountRate() public view returns (uint256 _rate) {
        uint256 _blobPrice = getBlobPrice();
        if (_blobPrice <= blobPriceOne) {
            if (discountPercent == 0) {
                // no discount
                _rate = blobPriceOne;
            } else {
                uint256 _bondAmount = blobPriceOne.mul(1e18).div(_blobPrice); // to burn 1 BLOB
                uint256 _discountAmount = _bondAmount.sub(blobPriceOne).mul(discountPercent).div(10000);
                _rate = blobPriceOne.add(_discountAmount);
                if (maxDiscountRate > 0 && _rate > maxDiscountRate) {
                    _rate = maxDiscountRate;
                }
            }
        }
    }

    function getBondPremiumRate() public view returns (uint256 _rate) {
        uint256 _blobPrice = getBlobPrice();
        if (_blobPrice > blobPriceCeiling) {
            uint256 _blobPricePremiumThreshold = blobPriceOne.mul(premiumThreshold).div(100);
            if (_blobPrice >= _blobPricePremiumThreshold) {
                //Price > 1.10
                uint256 _premiumAmount = _blobPrice.sub(blobPriceOne).mul(premiumPercent).div(10000);
                _rate = blobPriceOne.add(_premiumAmount);
                if (maxPremiumRate > 0 && _rate > maxPremiumRate) {
                    _rate = maxPremiumRate;
                }
            } else {
                // no premium bonus
                _rate = blobPriceOne;
            }
        }
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _blob,
        address _crab,
        address _shrimp,
        address _blobOracle,
        address _boardroom,
        uint256 _startTime
    ) public notInitialized {
        blob = _blob;
        crab = _crab;
        shrimp = _shrimp;
        blobOracle = _blobOracle;
        boardroom = _boardroom;
        startTime = _startTime;

        blobPriceOne = 10**18;
        blobPriceCeiling = blobPriceOne.mul(101).div(100);

        // Dynamic max expansion percent
        supplyTiers = [0 ether, 10000 ether, 15000 ether, 25000 ether, 35000 ether, 60000 ether, 250000 ether, 500000 ether, 1000000 ether];
        maxExpansionTiers = [450, 400, 350, 300, 250, 200, 150, 125, 100];

        maxSupplyExpansionPercent = 400; // Upto 4.0% supply for expansion

        bondDepletionFloorPercent = 10000; // 100% of Bond supply for depletion floor
        seigniorageExpansionFloorPercent = 3500; // At least 35% of expansion reserved for boardroom
        maxSupplyContractionPercent = 300; // Upto 3.0% supply for contraction (to burn BLOB and mint CRAB)
        maxDebtRatioPercent = 4000; // Upto 40% supply of CRAB to purchase

        premiumThreshold = 110;
        premiumPercent = 7000;

        // First 28 epochs with 2.5% expansion
        bootstrapEpochs = 28;
        bootstrapSupplyExpansionPercent = 250;

        // set seigniorageSaved to it's balance
        seigniorageSaved = IERC20(blob).balanceOf(address(this));

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

    function setBlobOracle(address _blobOracle) external onlyOperator {
        blobOracle = _blobOracle;
    }

    function setBlobPriceCeiling(uint256 _blobPriceCeiling) external onlyOperator {
        require(_blobPriceCeiling >= blobPriceOne && _blobPriceCeiling <= blobPriceOne.mul(120).div(100), "out of range"); // [$1.0, $1.2]
        blobPriceCeiling = _blobPriceCeiling;
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
        require(_daoFundSharedPercent <= 2500, "out of range"); // <= 25%
        require(_devFund != address(0), "zero");
        require(_devFundSharedPercent <= 500, "out of range"); // <= 5%
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
        require(_premiumThreshold >= blobPriceCeiling, "_premiumThreshold exceeds blobPriceCeiling");
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

    function _updateBlobPrice() internal {
        try IOracle(blobOracle).update() {} catch {}
    }

    function getBlobCirculatingSupply() public view returns (uint256) {
        IERC20 blobErc20 = IERC20(blob);
        uint256 totalSupply = blobErc20.totalSupply();
        uint256 balanceExcluded = 0;
        for (uint8 entryId = 0; entryId < excludedFromTotalSupply.length; ++entryId) {
            balanceExcluded = balanceExcluded.add(blobErc20.balanceOf(excludedFromTotalSupply[entryId]));
        }
        return totalSupply.sub(balanceExcluded);
    }

    function buyBonds(uint256 _blobAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_blobAmount > 0, "Treasury: cannot purchase bonds with zero amount");

        uint256 blobPrice = getBlobPrice();
        require(blobPrice == targetPrice, "Treasury: BLOB price moved");
        require(
            blobPrice < blobPriceOne, // price < $1
            "Treasury: blobPrice not eligible for bond purchase"
        );

        require(_blobAmount <= epochSupplyContractionLeft, "Treasury: not enough bond left to purchase");

        uint256 _rate = getBondDiscountRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _bondAmount = _blobAmount.mul(_rate).div(1e18);
        uint256 blobSupply = getBlobCirculatingSupply();
        uint256 newBondSupply = IERC20(crab).totalSupply().add(_bondAmount);
        require(newBondSupply <= blobSupply.mul(maxDebtRatioPercent).div(10000), "over max debt ratio");

        IBasisAsset(blob).burnFrom(msg.sender, _blobAmount);
        IBasisAsset(crab).mint(msg.sender, _bondAmount);

        epochSupplyContractionLeft = epochSupplyContractionLeft.sub(_blobAmount);
        _updateBlobPrice();

        emit BoughtBonds(msg.sender, _blobAmount, _bondAmount);
    }

    function redeemBonds(uint256 _bondAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_bondAmount > 0, "Treasury: cannot redeem bonds with zero amount");

        uint256 blobPrice = getBlobPrice();
        require(blobPrice == targetPrice, "Treasury: BLOB price moved");
        require(
            blobPrice > blobPriceCeiling, // price > $1.01
            "Treasury: blobPrice not eligible for bond purchase"
        );

        uint256 _rate = getBondPremiumRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _blobAmount = _bondAmount.mul(_rate).div(1e18);
        require(IERC20(blob).balanceOf(address(this)) >= _blobAmount, "Treasury: treasury has no more budget");

        seigniorageSaved = seigniorageSaved.sub(Math.min(seigniorageSaved, _blobAmount));

        IBasisAsset(crab).burnFrom(msg.sender, _bondAmount);
        IERC20(blob).safeTransfer(msg.sender, _blobAmount);

        _updateBlobPrice();

        emit RedeemedBonds(msg.sender, _blobAmount, _bondAmount);
    }

    function _sendToBoardroom(uint256 _amount) internal {
        IBasisAsset(blob).mint(address(this), _amount);

        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(10000);
            IERC20(blob).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(now, _daoFundSharedAmount);
        }

        uint256 _devFundSharedAmount = 0;
        if (devFundSharedPercent > 0) {
            _devFundSharedAmount = _amount.mul(devFundSharedPercent).div(10000);
            IERC20(blob).transfer(devFund, _devFundSharedAmount);
            emit DevFundFunded(now, _devFundSharedAmount);
        }

        _amount = _amount.sub(_daoFundSharedAmount).sub(_devFundSharedAmount);

        IERC20(blob).safeApprove(boardroom, 0);
        IERC20(blob).safeApprove(boardroom, _amount);
        IBoardroom(boardroom).allocateSeigniorage(_amount);
        emit BoardroomFunded(now, _amount);
    }

    function _calculateMaxSupplyExpansionPercent(uint256 _blobSupply) internal returns (uint256) {
        for (uint8 tierId = 8; tierId >= 0; --tierId) {
            if (_blobSupply >= supplyTiers[tierId]) {
                maxSupplyExpansionPercent = maxExpansionTiers[tierId];
                break;
            }
        }
        return maxSupplyExpansionPercent;
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        _updateBlobPrice();
        previousEpochBlobPrice = getBlobPrice();
        uint256 blobSupply = getBlobCirculatingSupply().sub(seigniorageSaved);
        if (epoch < bootstrapEpochs) {
            // 28 first epochs with 4.5% expansion
            _sendToBoardroom(blobSupply.mul(bootstrapSupplyExpansionPercent).div(10000));
        } else {
            if (previousEpochBlobPrice > blobPriceCeiling) {
                // Expansion ($BLOB Price > 1 $BUSD): there is some seigniorage to be allocated
                uint256 bondSupply = IERC20(crab).totalSupply();
                uint256 _percentage = previousEpochBlobPrice.sub(blobPriceOne);
                uint256 _savedForBond;
                uint256 _savedForBoardroom;
                uint256 _mse = _calculateMaxSupplyExpansionPercent(blobSupply).mul(1e14);
                if (_percentage > _mse) {
                    _percentage = _mse;
                }
                if (seigniorageSaved >= bondSupply.mul(bondDepletionFloorPercent).div(10000)) {
                    // saved enough to pay debt, mint as usual rate
                    _savedForBoardroom = blobSupply.mul(_percentage).div(1e18);
                } else {
                    // have not saved enough to pay debt, mint more
                    uint256 _seigniorage = blobSupply.mul(_percentage).div(1e18);
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
                    IBasisAsset(blob).mint(address(this), _savedForBond);
                    emit TreasuryFunded(now, _savedForBond);
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
        require(address(_token) != address(blob), "blob");
        require(address(_token) != address(crab), "bond");
        require(address(_token) != address(shrimp), "share");
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
