// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./SafeMath.sol";
import "./Address.sol";
import "./Math.sol";
import "./IERC165.sol";
import "./SafeERC20.sol";
import "./IERC721.sol";
import "./IOracle.sol";
import "./IBasisAsset.sol";
import "./IBoardroom.sol";
import "./IUniswapV2Router02.sol";
import "./ContractGuard.sol";
import "./Operator.sol";

interface ILKEY {
    function NFT_PRICE() external view returns (uint256);
}

contract Treasury is ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========= CONSTANT VARIABLES ======== */

    uint256 public constant PERIOD = 8 hours;

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
    address[] public excludedFromTotalSupply;

    // core components
    address public PETH;
    address public tbond;
    address public nft;

    address public boardroom;
    address public PETHOracle;

    // price
    uint256 public PETHPriceOne;
    uint256 public PETHPriceCeiling;

    uint256 public seigniorageSaved;

    uint256[] public supplyTiers;
    uint256[] public maxExpansionTiers;

    uint256 public maxSupplyExpansionPercent;
    uint256 public bondDepletionFloorPercent;
    uint256 public seigniorageExpansionFloorPercent;
    uint256 public maxSupplyContractionPercent;
    uint256 public maxDebtRatioPercent;

    // 21 first epochs (1 week) with 4.5% expansion regardless of PETH price
    uint256 public bootstrapEpochs;
    uint256 public bootstrapSupplyExpansionPercent;

    /* =================== Added variables =================== */
    uint256 public previousEpochPETHPrice;
    uint256 public maxDiscountRate; // when purchasing bond
    uint256 public maxPremiumRate; // when redeeming bond
    uint256 public discountPercent;
    uint256 public premiumThreshold;
    uint256 public premiumPercent;
    uint256 public mintingFactorForPayingDebt; // print extra PETH during debt phase

    address public daoFund;
    uint256 public daoFundSharedPercent;

    address public teamFund;
    uint256 public teamFundSharedPercent;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event BurnedBonds(address indexed from, uint256 bondAmount);
    event RedeemedBonds(address indexed from, uint256 PETHAmount, uint256 bondAmount);
    event BoughtBonds(address indexed from, uint256 PETHAmount, uint256 bondAmount);
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event BoardroomFunded(uint256 timestamp, uint256 seigniorage);
    event DaoFundFunded(uint256 timestamp, uint256 seigniorage);
    event TeamFundFunded(uint256 timestamp, uint256 seigniorage);

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
        epochSupplyContractionLeft = (getPETHPrice() > PETHPriceCeiling) ? 0 : getPETHCirculatingSupply().mul(maxSupplyContractionPercent).div(10000);
    }

    modifier checkOperator {
        require(
            IBasisAsset(PETH).operator() == address(this) &&
                IBasisAsset(tbond).operator() == address(this) &&
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
    function getPETHPrice() public view returns (uint256 PETHPrice) {
        try IOracle(PETHOracle).consult(PETH, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult PETH price from the oracle");
        }
    }

    function getPETHUpdatedPrice() public view returns (uint256 _PETHPrice) {
        try IOracle(PETHOracle).twap(PETH, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult PETH price from the oracle");
        }
    }

    // budget
    function getReserve() public view returns (uint256) {
        return seigniorageSaved;
    }

    function getBurnablePETHLeft() public view returns (uint256 _burnablePETHLeft) {
        uint256 _PETHPrice = getPETHPrice();
        if (_PETHPrice <= PETHPriceOne) {
            uint256 _PETHSupply = getPETHCirculatingSupply();
            uint256 _bondMaxSupply = _PETHSupply.mul(maxDebtRatioPercent).div(10000);
            uint256 _bondSupply = IERC20(tbond).totalSupply();
            if (_bondMaxSupply > _bondSupply) {
                uint256 _maxMintableBond = _bondMaxSupply.sub(_bondSupply);
                uint256 _maxBurnablePETH = _maxMintableBond.mul(_PETHPrice).div(1e18);
                _burnablePETHLeft = Math.min(epochSupplyContractionLeft, _maxBurnablePETH);
            }
        }
    }

    function getRedeemableBonds() public view returns (uint256 _redeemableBonds) {
        uint256 _PETHPrice = getPETHPrice();
        if (_PETHPrice > PETHPriceCeiling) {
            uint256 _totalPETH = IERC20(PETH).balanceOf(address(this));
            uint256 _rate = getBondPremiumRate();
            if (_rate > 0) {
                _redeemableBonds = _totalPETH.mul(1e18).div(_rate);
            }
        }
    }

    function getBondDiscountRate() public view returns (uint256 _rate) {
        uint256 _PETHPrice = getPETHPrice();
        if (_PETHPrice <= PETHPriceOne) {
            if (discountPercent == 0) {
                // no discount
                _rate = PETHPriceOne;
            } else {
                uint256 _bondAmount = PETHPriceOne.mul(1e18).div(_PETHPrice); // to burn 1 PETH
                uint256 _discountAmount = _bondAmount.sub(PETHPriceOne).mul(discountPercent).div(10000);
                _rate = PETHPriceOne.add(_discountAmount);
                if (maxDiscountRate > 0 && _rate > maxDiscountRate) {
                    _rate = maxDiscountRate;
                }
            }
        }
    }

    function getBondPremiumRate() public view returns (uint256 _rate) {
        uint256 _PETHPrice = getPETHPrice();
        if (_PETHPrice > PETHPriceCeiling) {
            uint256 _PETHPricePremiumThreshold = PETHPriceOne.mul(premiumThreshold).div(100);
            if (_PETHPrice >= _PETHPricePremiumThreshold) {
                //Price > 1.10
                uint256 _premiumAmount = _PETHPrice.sub(PETHPriceOne).mul(premiumPercent).div(10000);
                _rate = PETHPriceOne.add(_premiumAmount);
                if (maxPremiumRate > 0 && _rate > maxPremiumRate) {
                    _rate = maxPremiumRate;
                }
            } else {
                // no premium bonus
                _rate = PETHPriceOne;
            }
        }
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _PETH,
        address _tbond,
        address _nft,
        address _PETHOracle,
        address _boardroom,
        uint256 _startTime
    ) public notInitialized {
        PETH = _PETH;
        tbond = _tbond;
        nft = _nft;
        PETHOracle = _PETHOracle;
        boardroom = _boardroom;
        startTime = _startTime;

        PETHPriceOne = 10**16;  // 0.01 ETH
        PETHPriceCeiling = PETHPriceOne.mul(101).div(100);

        // Dynamic max expansion percent
        supplyTiers = [0 ether, 2000 ether, 3000 ether, 4000 ether, 5000 ether, 5500 ether, 6000 ether];
        maxExpansionTiers = [450, 350, 250, 150, 100, 50, 25];

        maxSupplyExpansionPercent = 400; // Upto 4.0% supply for expansion

        bondDepletionFloorPercent = 10000; // 100% of Bond supply for depletion floor
        seigniorageExpansionFloorPercent = 3500; // At least 35% of expansion reserved for boardroom
        maxSupplyContractionPercent = 300; // Upto 3.0% supply for contraction (to burn PETH and mint cBOND)
        maxDebtRatioPercent = 3500; // Upto 35% supply of cBOND to purchase

        premiumThreshold = 110;
        premiumPercent = 7000;

        // First 21 epochs with 2.5% expansion
        bootstrapEpochs = 21;
        bootstrapSupplyExpansionPercent = 250;

        // set seigniorageSaved to it's balance
        seigniorageSaved = IERC20(PETH).balanceOf(address(this));

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

    function setPETHOracle(address _PETHOracle) external onlyOperator {
        PETHOracle = _PETHOracle;
    }

    function setPETHPriceCeiling(uint256 _PETHPriceCeiling) external onlyOperator {
        require(_PETHPriceCeiling >= PETHPriceOne && _PETHPriceCeiling <= PETHPriceOne.mul(120).div(100), "out of range"); // [$1.0, $1.2]
        PETHPriceCeiling = _PETHPriceCeiling;
    }

    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent) external onlyOperator {
        require(_maxSupplyExpansionPercent >= 10 && _maxSupplyExpansionPercent <= 1000, "_maxSupplyExpansionPercent: out of range"); // [0.1%, 10%]
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
    }

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
        require(_bootstrapSupplyExpansionPercent >= 100 && _bootstrapSupplyExpansionPercent <= 1000, "_bootstrapSupplyExpansionPercent: out of range"); // [1%, 10%]
        bootstrapEpochs = _bootstrapEpochs;
        bootstrapSupplyExpansionPercent = _bootstrapSupplyExpansionPercent;
    }

    function setExtraFunds(
        address _daoFund,
        uint256 _daoFundSharedPercent,
        address _teamFund,
        uint256 _teamFundSharedPercent
    ) external onlyOperator {
        require(_daoFund != address(0), "zero");
        require(_daoFundSharedPercent <= 2500, "out of range"); // <= 25%
        require(_teamFund != address(0), "zero");
        require(_teamFundSharedPercent <= 2500, "out of range"); // <= 25%
        daoFund = _daoFund;
        daoFundSharedPercent = _daoFundSharedPercent;
        teamFund = _teamFund;
        teamFundSharedPercent = _teamFundSharedPercent;
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
        require(_premiumThreshold >= PETHPriceCeiling, "_premiumThreshold exceeds PETHPriceCeiling");
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

    function _updatePETHPrice() internal {
        try IOracle(PETHOracle).update() {} catch {}
    }

    function getPETHCirculatingSupply() public view returns (uint256) {
        IERC20 PETHErc20 = IERC20(PETH);
        uint256 totalSupply = PETHErc20.totalSupply();
        uint256 balanceExcluded = 0;
        for (uint8 entryId = 0; entryId < excludedFromTotalSupply.length; ++entryId) {
            balanceExcluded = balanceExcluded.add(PETHErc20.balanceOf(excludedFromTotalSupply[entryId]));
        }
        return totalSupply.sub(balanceExcluded);
    }

    function buyBonds(uint256 _PETHAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_PETHAmount > 0, "Treasury: cannot purchase bonds with zero amount");

        uint256 PETHPrice = getPETHPrice();
        require(PETHPrice == targetPrice, "Treasury: PETH price moved");
        require(
            PETHPrice < PETHPriceOne, // price < $1
            "Treasury: PETHPrice not eligible for bond purchase"
        );

        require(_PETHAmount <= epochSupplyContractionLeft, "Treasury: not enough bond left to purchase");

        uint256 _rate = getBondDiscountRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _bondAmount = _PETHAmount.mul(_rate).div(1e18);
        uint256 PETHSupply = getPETHCirculatingSupply();
        uint256 newBondSupply = IERC20(tbond).totalSupply().add(_bondAmount);
        require(newBondSupply <= PETHSupply.mul(maxDebtRatioPercent).div(10000), "over max debt ratio");

        IBasisAsset(PETH).burnFrom(msg.sender, _PETHAmount);
        IBasisAsset(tbond).mint(msg.sender, _bondAmount);

        epochSupplyContractionLeft = epochSupplyContractionLeft.sub(_PETHAmount);
        _updatePETHPrice();

        emit BoughtBonds(msg.sender, _PETHAmount, _bondAmount);
    }

    function redeemBonds(uint256 _bondAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_bondAmount > 0, "Treasury: cannot redeem bonds with zero amount");

        uint256 PETHPrice = getPETHPrice();
        require(PETHPrice == targetPrice, "Treasury: PETH price moved");
        require(
            PETHPrice > PETHPriceCeiling, // price > $1.01
            "Treasury: PETHPrice not eligible for bond purchase"
        );

        uint256 _rate = getBondPremiumRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _PETHAmount = _bondAmount.mul(_rate).div(1e18);
        require(IERC20(PETH).balanceOf(address(this)) >= _PETHAmount, "Treasury: treasury has no more budget");

        seigniorageSaved = seigniorageSaved.sub(Math.min(seigniorageSaved, _PETHAmount));

        IBasisAsset(tbond).burnFrom(msg.sender, _bondAmount);
        IERC20(PETH).safeTransfer(msg.sender, _PETHAmount);

        _updatePETHPrice();

        emit RedeemedBonds(msg.sender, _PETHAmount, _bondAmount);
    }

    function _sendToBoardroom(uint256 _amount) internal {
        IBasisAsset(PETH).mint(address(this), _amount);

        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(10000);
            IERC20(PETH).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(block.timestamp, _daoFundSharedAmount);
        }

        uint256 _teamFundSharedAmount = 0;
        if(teamFundSharedPercent > 0) {
            _teamFundSharedAmount = _amount.mul(teamFundSharedPercent).div(10000);
            IERC20(PETH).transfer(teamFund, _teamFundSharedAmount);
            emit TeamFundFunded(block.timestamp, _teamFundSharedAmount);
        }

        _amount = _amount
            .sub(_daoFundSharedAmount)
            .sub(_teamFundSharedAmount);

        IERC20(PETH).safeApprove(boardroom, 0);
        IERC20(PETH).safeApprove(boardroom, _amount);
        IBoardroom(boardroom).allocateSeigniorage(_amount);
        emit BoardroomFunded(block.timestamp, _amount);
    }

    function _calculateMaxSupplyExpansionPercent(uint256 _PETHSupply) internal returns (uint256) {
        for (uint8 tierId = 6; tierId >= 0; --tierId) {
            if (_PETHSupply >= supplyTiers[tierId]) {
                maxSupplyExpansionPercent = maxExpansionTiers[tierId];
                break;
            }
        }
        return maxSupplyExpansionPercent;
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        _updatePETHPrice();
        previousEpochPETHPrice = getPETHPrice();
        uint256 nftPriceInETH = ILKEY(nft).NFT_PRICE();
        uint256 PETHSupply = getPETHCirculatingSupply().sub(seigniorageSaved);
        uint256 stakedNfts = IERC721(nft).balanceOf(boardroom);
        uint256 boardroomBaseSupply = stakedNfts.mul(nftPriceInETH).div(PETHPriceOne).mul(1e18);
        if (epoch < bootstrapEpochs) {
            // 21 first epochs with 2.5% expansion
            uint256 _savedForBoardroom = boardroomBaseSupply.mul(bootstrapSupplyExpansionPercent).div(10000);
            _sendToBoardroom(_savedForBoardroom);
        } else {
            if (previousEpochPETHPrice > PETHPriceCeiling) {
                uint256 bondSupply = IERC20(tbond).totalSupply();
                uint256 _percentage = previousEpochPETHPrice.sub(PETHPriceOne);
                uint256 _savedForBond;
                uint256 _savedForBoardroom;
                uint256 _mse = _calculateMaxSupplyExpansionPercent(PETHSupply).mul(1e14);

                if (_percentage > _mse) {
                    _percentage = _mse;
                }
                if (seigniorageSaved >= bondSupply.mul(bondDepletionFloorPercent).div(10000)) {
                    // saved enough to pay debt, mint as usual rate
                    _savedForBoardroom = boardroomBaseSupply.mul(_percentage).div(1e18);
                } else {
                    // have not saved enough to pay debt, mint more
                    uint256 _seigniorage = boardroomBaseSupply.mul(_percentage).div(1e18);
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
                    IBasisAsset(PETH).mint(address(this), _savedForBond);
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
        require(address(_token) != address(PETH), "PETH");
        require(address(_token) != address(tbond), "bond");
        require(address(_token) != address(nft), "nft");
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
