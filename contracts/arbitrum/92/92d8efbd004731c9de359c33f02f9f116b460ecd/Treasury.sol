// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Math.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

import "./Babylonian.sol";
import "./Operator.sol";
import "./ContractGuard.sol";
import "./IBasisAsset.sol";
import "./IOracle.sol";
import "./IShelter.sol";
import "./Operator.sol";

contract Treasury is ContractGuard, Operator {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========= CONSTANT VARIABLES ======== */

    uint256 public constant PERIOD = 6 hours;

    /* ========== STATE VARIABLES ========== */

    // flags
    bool public initialized = false;

    // epoch
    uint256 public startTime;
    uint256 public epoch = 0;
    uint256 public epochSupplyContractionLeft = 0;

    //=================================================================// exclusions from total supply
    address[] public excludedFromTotalSupply;

    // core components
    address public aur;
    address public gbond;
    address public gshare;

    address public shelter;
    address public aurOracle;

    // price
    address public aurPriceOneOracle;
    uint256 public aurPriceCeilingPercent = 10500; // 105% of aurPriceOne

    uint256 public seigniorageSaved;

    uint256[] public supplyTiers;
    uint256[] public maxExpansionTiers;

    uint256 public maxSupplyExpansionPercent;
    uint256 public bondDepletionFloorPercent;
    uint256 public seigniorageExpansionFloorPercent;
    uint256 public maxSupplyContractionPercent;
    uint256 public maxDebtRatioPercent;

    // 14 first epochs (0.5 week) with 4.5% expansion regardless of AUR price
    uint256 public bootstrapEpochs;
    uint256 public bootstrapSupplyExpansionPercent;

    /* =================== Added variables =================== */
    uint256 public previousEpochAurPrice;
    uint256 public maxDiscountRate; // when purchasing bond
    uint256 public maxPremiumRate; // when redeeming bond
    uint256 public discountPercent;
    uint256 public premiumThreshold;
    uint256 public premiumPercent;
    uint256 public mintingFactorForPayingDebt; // print extra AUR during debt phase

    address public daoFund;
    uint256 public daoFundSharedPercent;

    //=================================================//

    address public devFund;
    uint256 public devFundSharedPercent;
    address public teamFund;
    uint256 public teamFundSharedPercent;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event BurnedBonds(address indexed from, uint256 bondAmount);
    event RedeemedBonds(address indexed from, uint256 aurAmount, uint256 bondAmount);
    event BoughtBonds(address indexed from, uint256 aurAmount, uint256 bondAmount);
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event ShelterFunded(uint256 timestamp, uint256 seigniorage);
    event DaoFundFunded(uint256 timestamp, uint256 seigniorage);
    event DevFundFunded(uint256 timestamp, uint256 seigniorage);
    event TeamFundFunded(uint256 timestamp, uint256 seigniorage);
    event AurPriceOneOracleUpdated(address indexed _aurPriceOneOracle);

    /* =================== Modifier =================== */

    modifier checkCondition() {
        require(block.timestamp >= startTime, "Treasury: not started yet");

        _;
    }

    modifier checkEpoch() {
        require(block.timestamp >= nextEpochPoint(), "Treasury: not opened yet");

        _;

        epoch = epoch.add(1);
        epochSupplyContractionLeft = (getAurPrice() > aurPriceOneCeiling())
            ? 0
            : getAurCirculatingSupply().mul(maxSupplyContractionPercent).div(10000);
    }

    modifier checkOperator() {
        require(
            IBasisAsset(aur).operator() == address(this) && IBasisAsset(gbond).operator() == address(this)
                && IBasisAsset(gshare).operator() == address(this) && Operator(shelter).operator() == address(this),
            "Treasury: need more permission"
        );

        _;
    }

    modifier notInitialized() {
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
    function getAurPrice() public view returns (uint256 aurPrice) {
        try IOracle(aurOracle).consult(aur, 1e18) returns (uint144 price) {
            aurPrice = uint256(price);
        } catch {
            revert("Treasury: failed to consult AUR price from the oracle");
        }
    }

    function getAurUpdatedPrice() public view returns (uint256 _aurPrice) {
        try IOracle(aurOracle).twap(aur, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult AUR price from the oracle");
        }
    }

    function aurPriceOne() public view returns (uint256) {
        try IOracle(aurPriceOneOracle).consult(aur, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult AUR price from the oracle");
        }
    }

    function aurPriceOneCeiling() public view returns (uint256) {
        return aurPriceOne().mul(aurPriceCeilingPercent).div(10000);
    }

    // budget
    function getReserve() public view returns (uint256) {
        return seigniorageSaved;
    }

    function getBurnableAurLeft() public view returns (uint256 _burnableAurLeft) {
        uint256 _aurPrice = getAurPrice();
        if (_aurPrice <= aurPriceOne()) {
            uint256 _aurSupply = getAurCirculatingSupply();
            uint256 _bondMaxSupply = _aurSupply.mul(maxDebtRatioPercent).div(10000);
            uint256 _bondSupply = IERC20(gbond).totalSupply();
            if (_bondMaxSupply > _bondSupply) {
                uint256 _maxMintableBond = _bondMaxSupply.sub(_bondSupply);
                uint256 _maxBurnableAur = _maxMintableBond.mul(_aurPrice).div(1e18);
                _burnableAurLeft = Math.min(epochSupplyContractionLeft, _maxBurnableAur);
            }
        }
    }

    function getRedeemableBonds() public view returns (uint256 _redeemableBonds) {
        uint256 _aurPrice = getAurPrice();
        if (_aurPrice > aurPriceOneCeiling()) {
            uint256 _totalAur = IERC20(aur).balanceOf(address(this));
            uint256 _rate = getBondPremiumRate();
            if (_rate > 0) {
                _redeemableBonds = _totalAur.mul(1e18).div(_rate);
            }
        }
    }

    function getBondDiscountRate() public view returns (uint256 _rate) {
        uint256 _aurPrice = getAurPrice();
        if (_aurPrice <= aurPriceOne()) {
            if (discountPercent == 0) {
                // no discount
                _rate = aurPriceOne();
            } else {
                uint256 _bondAmount = aurPriceOne().mul(1e18).div(_aurPrice); // to burn 1 AUR
                uint256 _discountAmount = _bondAmount.sub(aurPriceOne()).mul(discountPercent).div(10000);
                _rate = aurPriceOne().add(_discountAmount);
                if (maxDiscountRate > 0 && _rate > maxDiscountRate) {
                    _rate = maxDiscountRate;
                }
            }
        }
    }

    function getBondPremiumRate() public view returns (uint256 _rate) {
        uint256 _aurPrice = getAurPrice();
        uint256 _aurPriceOne = aurPriceOne();
        if (_aurPrice > aurPriceOneCeiling()) {
            uint256 _aurPricePremiumThreshold = _aurPriceOne.mul(premiumThreshold).div(100);
            if (_aurPrice >= _aurPricePremiumThreshold) {
                //Price > 1.10
                uint256 _premiumAmount = _aurPrice.sub(_aurPriceOne).mul(premiumPercent).div(10000);
                _rate = _aurPriceOne.add(_premiumAmount);
                if (maxPremiumRate > 0 && _rate > maxPremiumRate) {
                    _rate = maxPremiumRate;
                }
            } else {
                // no premium bonus
                _rate = _aurPriceOne;
            }
        }
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _aur,
        address _gbond,
        address _gshare,
        address _aurOracle,
        address _shelter,
        uint256 _startTime,
        address _genesisRewardPool
    ) public notInitialized onlyOperator {
        excludedFromTotalSupply.push(_genesisRewardPool);
        aur = _aur;
        gbond = _gbond;
        gshare = _gshare;
        aurOracle = _aurOracle;
        shelter = _shelter;
        startTime = _startTime;

        // Dynamic max expansion percent
        supplyTiers = [0 ether, 206000 ether, 386000 ether, 530000 ether, 1300000 ether, 5000000 ether, 10000000 ether];
        maxExpansionTiers = [600, 500, 450, 400, 200, 100, 50];

        maxSupplyExpansionPercent = 600; // Upto 6% supply for expansion

        bondDepletionFloorPercent = 10000; // 100% of Bond supply for depletion floor
        seigniorageExpansionFloorPercent = 3500; // At least 35% of expansion reserved for shelter
        maxSupplyContractionPercent = 300; // Upto 3.0% supply for contraction (to burn AUR and mint gBOND)
        maxDebtRatioPercent = 3500; // Upto 35% supply of gBOND to purchase

        premiumThreshold = 110;
        premiumPercent = 7000;

        // First 14 epochs with 6% expansion
        bootstrapEpochs = 14;
        bootstrapSupplyExpansionPercent = 600;

        // set seigniorageSaved to it's balance
        seigniorageSaved = IERC20(aur).balanceOf(address(this));

        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        transferOperator(_operator);
    }

    function renounceOperator() external onlyOperator {
        _renounceOperator();
    }

    function setShelter(address _shelter) external onlyOperator {
        shelter = _shelter;
    }

    function setAurOracle(address _aurOracle) external onlyOperator {
        aurOracle = _aurOracle;
    }

    function setAurPriceCeiling(uint256 _maxPercent) external onlyOperator {
        require(_maxPercent >= 10000 && _maxPercent <= 12000, "out of range"); // [1.00%, 1.20%]
        aurPriceCeilingPercent = _maxPercent;
    }

    function setAurPriceOneOracle(address _aurPriceOneOracle) external onlyOperator {
        require(_aurPriceOneOracle != address(0), "zero address");
        aurPriceOneOracle = _aurPriceOneOracle;
        emit AurPriceOneOracleUpdated(_aurPriceOneOracle);
    }

    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent) external onlyOperator {
        require(
            _maxSupplyExpansionPercent >= 10 && _maxSupplyExpansionPercent <= 1000,
            "_maxSupplyExpansionPercent: out of range"
        ); // [0.1%, 10%]
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
    }
    // =================== ALTER THE NUMBERS IN LOGIC!!!! =================== //

    function setSupplyTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 7, "Index has to be lower than count of tiers");
        if (_index > 0) {
            require(_value > supplyTiers[_index - 1]);
        }
        if (_index < 6) {
            require(_value < supplyTiers[_index + 1]);
        }
        supplyTiers[_index] = _value;
        return true;
    }

    function setMaxExpansionTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 7, "Index has to be lower than count of tiers");
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
        require(
            _bootstrapSupplyExpansionPercent >= 100 && _bootstrapSupplyExpansionPercent <= 1000,
            "_bootstrapSupplyExpansionPercent: out of range"
        ); // [1%, 10%]
        bootstrapEpochs = _bootstrapEpochs;
        bootstrapSupplyExpansionPercent = _bootstrapSupplyExpansionPercent;
    }
    //======================================================================

    function setExtraFunds(
        address _daoFund,
        uint256 _daoFundSharedPercent,
        address _devFund,
        uint256 _devFundSharedPercent,
        address _teamFund,
        uint256 _teamFundSharedPercent
    ) external onlyOperator {
        require(_daoFund != address(0), "zero");
        require(_daoFundSharedPercent <= 1500, "out of range");
        require(_devFund != address(0), "zero");
        require(_devFundSharedPercent <= 350, "out of range");
        require(_teamFund != address(0), "zero");
        require(_teamFundSharedPercent <= 550, "out of range");

        daoFund = _daoFund;
        daoFundSharedPercent = _daoFundSharedPercent;
        devFund = _devFund;
        devFundSharedPercent = _devFundSharedPercent;
        teamFund = _teamFund;
        teamFundSharedPercent = _teamFundSharedPercent;
    }

    function setMaxDiscountRate(uint256 _maxDiscountRate) external onlyOperator {
        require(_maxDiscountRate <= 20000, "_maxDiscountRate is over 200%");
        maxDiscountRate = _maxDiscountRate;
    }

    function setMaxPremiumRate(uint256 _maxPremiumRate) external onlyOperator {
        require(_maxPremiumRate <= 20000, "_maxPremiumRate is over 200%");
        maxPremiumRate = _maxPremiumRate;
    }

    function setDiscountPercent(uint256 _discountPercent) external onlyOperator {
        require(_discountPercent <= 20000, "_discountPercent is over 200%");
        discountPercent = _discountPercent;
    }

    function setPremiumThreshold(uint256 _premiumThreshold) external onlyOperator {
        require(_premiumThreshold >= 100, "_premiumThreshold is lower than 1");
        require(_premiumThreshold <= 150, "_premiumThreshold is higher than 1.5");
        premiumThreshold = _premiumThreshold;
    }

    function setPremiumPercent(uint256 _premiumPercent) external onlyOperator {
        require(_premiumPercent <= 20000, "_premiumPercent is over 200%");
        premiumPercent = _premiumPercent;
    }

    function setMintingFactorForPayingDebt(uint256 _mintingFactorForPayingDebt) external onlyOperator {
        require(
            _mintingFactorForPayingDebt >= 10000 && _mintingFactorForPayingDebt <= 20000,
            "_mintingFactorForPayingDebt: out of range"
        ); // [100%, 200%]
        mintingFactorForPayingDebt = _mintingFactorForPayingDebt;
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    function _updateAurPrice() internal {
        try IOracle(aurOracle).update() {} catch {}
    }

    function getAurCirculatingSupply() public view returns (uint256) {
        IERC20 aurErc20 = IERC20(aur);
        uint256 totalSupply = aurErc20.totalSupply();
        uint256 balanceExcluded = 0;
        for (uint8 entryId = 0; entryId < excludedFromTotalSupply.length; ++entryId) {
            balanceExcluded = balanceExcluded.add(aurErc20.balanceOf(excludedFromTotalSupply[entryId]));
        }
        return totalSupply.sub(balanceExcluded);
    }

    function buyBonds(uint256 _aurAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_aurAmount > 0, "Treasury: cannot purchase bonds with zero amount");

        uint256 aurPrice = getAurPrice();
        require(aurPrice == targetPrice, "Treasury: AUR price moved");
        require(
            aurPrice < aurPriceOne(), // price < $1
            "Treasury: aurPrice not eligible for bond purchase"
        );

        require(_aurAmount <= epochSupplyContractionLeft, "Treasury: not enough bond left to purchase");

        uint256 _rate = getBondDiscountRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _bondAmount = _aurAmount.mul(_rate).div(1e18);
        uint256 aurSupply = getAurCirculatingSupply();
        uint256 negBondSupply = IERC20(gbond).totalSupply().add(_bondAmount);
        require(negBondSupply <= aurSupply.mul(maxDebtRatioPercent).div(10000), "over max debt ratio");

        IBasisAsset(aur).burnFrom(msg.sender, _aurAmount);
        IBasisAsset(gbond).mint(msg.sender, _bondAmount);

        epochSupplyContractionLeft = epochSupplyContractionLeft.sub(_aurAmount);
        _updateAurPrice();

        emit BoughtBonds(msg.sender, _aurAmount, _bondAmount);
    }

    function redeemBonds(uint256 _bondAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_bondAmount > 0, "Treasury: cannot redeem bonds with zero amount");

        uint256 aurPrice = getAurPrice();
        require(aurPrice == targetPrice, "Treasury: AUR price moved");
        require(
            aurPrice > aurPriceOneCeiling(), // price > $1.01
            "Treasury: aurPrice not eligible for bond purchase"
        );

        uint256 _rate = getBondPremiumRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _aurAmount = _bondAmount.mul(_rate).div(1e18);
        require(IERC20(aur).balanceOf(address(this)) >= _aurAmount, "Treasury: treasury has no more budget");

        seigniorageSaved = seigniorageSaved.sub(Math.min(seigniorageSaved, _aurAmount));

        IBasisAsset(gbond).burnFrom(msg.sender, _bondAmount);
        IERC20(aur).safeTransfer(msg.sender, _aurAmount);

        _updateAurPrice();

        emit RedeemedBonds(msg.sender, _aurAmount, _bondAmount);
    }

    function _sendToShelter(uint256 _amount) internal {
        IBasisAsset(aur).mint(address(this), _amount);

        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(10000);
            IERC20(aur).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(block.timestamp, _daoFundSharedAmount);
        }

        uint256 _devFundSharedAmount = 0;
        if (devFundSharedPercent > 0) {
            _devFundSharedAmount = _amount.mul(devFundSharedPercent).div(10000);
            IERC20(aur).transfer(devFund, _devFundSharedAmount);
            emit DevFundFunded(block.timestamp, _devFundSharedAmount);
        }

        uint256 _teamFundSharedAmount = 0;
        if (teamFundSharedPercent > 0) {
            _teamFundSharedAmount = _amount.mul(teamFundSharedPercent).div(10000);
            IERC20(aur).transfer(teamFund, _teamFundSharedAmount);
            emit TeamFundFunded(block.timestamp, _teamFundSharedAmount);
        }

        _amount = _amount.sub(_daoFundSharedAmount).sub(_devFundSharedAmount).sub(_teamFundSharedAmount);

        IERC20(aur).safeApprove(shelter, 0);
        IERC20(aur).safeApprove(shelter, _amount);
        IShelter(shelter).allocateSeigniorage(_amount);
        emit ShelterFunded(block.timestamp, _amount);
    }

    function _calculateMaxSupplyExpansionPercent(uint256 _aurSupply) internal returns (uint256) {
        for (uint8 tierId = 6; tierId >= 0; --tierId) {
            if (_aurSupply >= supplyTiers[tierId]) {
                maxSupplyExpansionPercent = maxExpansionTiers[tierId];
                break;
            }
        }
        return maxSupplyExpansionPercent;
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        _updateAurPrice();
        previousEpochAurPrice = getAurPrice();
        uint256 aurSupply = getAurCirculatingSupply().sub(seigniorageSaved);
        if (epoch < bootstrapEpochs) {
            // 14 first epochs with 6% expansion
            _sendToShelter(aurSupply.mul(bootstrapSupplyExpansionPercent).div(10000));
        } else {
            if (previousEpochAurPrice > aurPriceOneCeiling()) {
                // Expansion ($AUR Price > 1 $FTM): there is some seigniorage to be allocated
                uint256 bondSupply = IERC20(gbond).totalSupply();
                uint256 _percentage = previousEpochAurPrice.sub(aurPriceOne());
                uint256 _savedForBond;
                uint256 _savedForShelter;
                uint256 _mse = _calculateMaxSupplyExpansionPercent(aurSupply).mul(1e14);
                if (_percentage > _mse) {
                    _percentage = _mse;
                }
                if (seigniorageSaved >= bondSupply.mul(bondDepletionFloorPercent).div(10000)) {
                    // saved enough to pay debt, mint as usual rate
                    _savedForShelter = aurSupply.mul(_percentage).div(1e18);
                } else {
                    // have not saved enough to pay debt, mint more
                    uint256 _seigniorage = aurSupply.mul(_percentage).div(1e18);
                    _savedForShelter = _seigniorage.mul(seigniorageExpansionFloorPercent).div(10000);
                    _savedForBond = _seigniorage.sub(_savedForShelter);
                    if (mintingFactorForPayingDebt > 0) {
                        _savedForBond = _savedForBond.mul(mintingFactorForPayingDebt).div(10000);
                    }
                }
                if (_savedForShelter > 0) {
                    _sendToShelter(_savedForShelter);
                }
                if (_savedForBond > 0) {
                    seigniorageSaved = seigniorageSaved.add(_savedForBond);
                    IBasisAsset(aur).mint(address(this), _savedForBond);
                    emit TreasuryFunded(block.timestamp, _savedForBond);
                }
            }
        }
    }
    //===================================================================================================================================

    function governanceRecoverUnsupported(IERC20 _token, uint256 _amount, address _to) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(aur), "aur");
        require(address(_token) != address(gbond), "bond");
        require(address(_token) != address(gshare), "share");
        _token.safeTransfer(_to, _amount);
    }

    function shelterSetOperator(address _operator) external onlyOperator {
        IShelter(shelter).setOperator(_operator);
    }

    function shelterSetLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        IShelter(shelter).setLockUp(_withdrawLockupEpochs, _rewardLockupEpochs);
    }

    function shelterAllocateSeigniorage(uint256 amount) external onlyOperator {
        IShelter(shelter).allocateSeigniorage(amount);
    }

    function shelterGovernanceRecoverUnsupported(address _token, uint256 _amount, address _to) external onlyOperator {
        IShelter(shelter).governanceRecoverUnsupported(_token, _amount, _to);
    }
}

