pragma solidity 0.8.17;

import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { ERC721Enumerable, ERC721 } from "./ERC721Enumerable.sol";
import { GlobalACL, Auth } from "./Auth.sol";
import { OracleWrapper } from "./OracleWrapper.sol";
import { ArbVault } from "./ArbVault.sol";
import { ERC20 } from "./tokens_ERC20.sol";
import { SafeTransferLib } from "./SafeTransferLib.sol";
import { OARB } from "./oARB.sol";

/**
 * @title   Vester
 * @author  UmamiDAO
 *
 * An implementation of the IVester interface that allows users to buy ARB
 * at a discount if they vest ARB and oARB for a certain time
 */
contract Vester is ERC721Enumerable, GlobalACL, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for OARB;

    // ===================================================
    // ==================== Constants ====================
    // ===================================================

    uint256 private constant BIPS = 10_000;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // =================================================
    // ==================== Structs ====================
    // =================================================

    struct VestingPosition {
        address creator;
        uint256 id;
        uint256 startTime;
        uint256 duration;
        uint256 amount;
    }

    // ================================================
    // ==================== Events ====================
    // ================================================

    event Vesting(address indexed owner, uint256 duration, uint256 amount, uint256 vestingId);
    event PositionClosed(address indexed owner, uint256 vestingId);
    event EmergencyWithdraw(address indexed owner, uint256 vestingId);
    event VestingActiveSet(bool vestingActive);
    event ForceCloseActiveSet(bool forceCloseActive);
    event OARBSet(address oARB);
    event ClosePositionWindowSet(uint256 _closePositionWindow);
    event EmergencyWithdrawTaxSet(uint256 _emergencyWithdrawTax);
    event SetPriceFeed(address _newPriceFeed);
    event SetTreasury(address _newTreasury);
    event SetArbVault(address _newArbVault);
    event SetDurations(uint256 _minDuration, uint256 _maxDuration);
    event SetLiquidatorDiscount(uint256 _liquidatorDiscount);

    // ===================================================
    // ==================== State Variables ====================
    // ===================================================

    ERC20 public immutable ARB; // solhint-disable-line
    uint256 private _nextId;
    mapping(uint256 => VestingPosition) public vestingPositions;
    uint256 public promisedArbTokens;
    OARB public oARB;
    OracleWrapper public priceFeed;
    ArbVault public vault;
    address public treasury;

    uint256 public closePositionWindow = 14 days;
    uint256 public emergencyWithdrawTax;
    bool public vestingActive;
    bool public forceCloseActive;

    uint256 public minDuration = 1 weeks;
    uint256 public maxDuration = 16 weeks;
    uint256 public liquidatorDiscount = 200;

    // ==================================================================
    // ======================= Modifiers =======================
    // ==================================================================

    modifier requireVestingActive() {
        require(vestingActive, "Vesting not active");
        _;
    }

    // ==================================================================
    // ======================= Constructor =======================
    // ==================================================================

    constructor(ERC20 _arb, OARB _oARB, Auth _auth, address _treasury, OracleWrapper _priceFeed, ArbVault _vault)
        ERC721("UmamiArbVesting", "UAV")
        GlobalACL(_auth)
    {
        ARB = _arb;
        oARB = _oARB;
        priceFeed = _priceFeed;
        treasury = _treasury;
        vault = _vault;
    }

    // ==================================================================
    // ======================= External Functions =======================
    // ==================================================================

    function vest(uint256 _amount, uint256 _duration) external requireVestingActive returns (uint256) {
        require(_amount > 0, "Amount !> 0");
        require(ARB.balanceOf(address(vault)) >= _amount + promisedArbTokens, "Arb Unavailable");
        require(_duration >= minDuration && _duration <= maxDuration && _duration % 1 weeks == 0, "Invalid duration");

        // Create vesting position NFT
        uint256 nftId = ++_nextId;
        vestingPositions[nftId] = VestingPosition({
            creator: msg.sender,
            id: nftId,
            startTime: block.timestamp,
            duration: _duration,
            amount: _amount
        });
        _mint(msg.sender, nftId);

        // Transfer amounts into contract
        oARB.safeTransferFrom(msg.sender, address(this), _amount);
        ARB.safeTransferFrom(msg.sender, address(this), _amount);

        // reserve arb
        promisedArbTokens += _amount;
        emit Vesting(msg.sender, _duration, _amount, nftId);
        return nftId;
    }

    function closePositionAndBuyTokens(uint256 _id) external payable nonReentrant {
        VestingPosition memory _position = vestingPositions[_id];
        address owner = ownerOf(_id);

        require(owner != address(0), "Owner invalid");
        require(owner == msg.sender, "Invalid position owner");
        require(block.timestamp > _position.startTime + _position.duration, "Position not vested");
        require(block.timestamp <= _position.startTime + _position.duration + closePositionWindow, "Position expired");

        // Calculate price
        uint256 discount = _calculateDiscount(_position.duration, false);
        uint256 wethPrice = _getTokenPrice(WETH);
        uint256 arbPriceAdj = (_getTokenPrice(address(ARB)) * discount) / BIPS;
        uint256 wethValue = msg.value * wethPrice;
        uint256 arbValue = _position.amount * arbPriceAdj;
        uint256 cost = _position.amount * arbPriceAdj / wethPrice;

        require(wethValue >= arbValue, "Insufficient msg.value");

        oARB.burn(_position.amount);
        // pull from vault to back promise
        vault.vestArb(owner, _position.amount);
        // transfer arb back to the owner
        ARB.safeTransfer(owner, _position.amount);
        // send refund and cost
        uint256 refund = msg.value - cost;
        SafeTransferLib.safeTransferETH(treasury, cost);
        if (refund > 0) SafeTransferLib.safeTransferETH(owner, refund);

        // clear from state
        promisedArbTokens -= _position.amount;
        _burn(_id);
        delete vestingPositions[_id];
        emit PositionClosed(owner, _id);
    }

    // @follow-up Who should this be callable by? Operator?
    function forceClosePosition(uint256 _id) external payable nonReentrant {
        VestingPosition memory _position = vestingPositions[_id];
        address owner = ownerOf(_id);
        require(owner != address(0), "Owner invalid");
        require(
            block.timestamp > _position.startTime + _position.duration + closePositionWindow, "Position not expired"
        );
        require(forceCloseActive, "Force close not active");

        // Calculate price
        uint256 discount = _calculateDiscount(_position.duration, true);
        uint256 wethPrice = _getTokenPrice(WETH);
        uint256 arbPriceAdj = (_getTokenPrice(address(ARB)) * (discount)) / BIPS;
        uint256 wethValue = msg.value * wethPrice;
        uint256 arbValue = _position.amount * arbPriceAdj;
        uint256 cost = _position.amount * arbPriceAdj / wethPrice;

        require(wethValue >= arbValue, "Insufficient msg.value");

        oARB.burn(_position.amount);

        // pull from vault to the liquidator
        vault.vestArb(msg.sender, _position.amount);

        // transfer arb to user
        ARB.safeTransfer(owner, _position.amount);

        // send refund and cost
        uint256 refund = msg.value - cost;
        SafeTransferLib.safeTransferETH(treasury, cost);
        if (refund > 0) SafeTransferLib.safeTransferETH(msg.sender, refund);

        promisedArbTokens -= _position.amount;
        _burn(_id);
        delete vestingPositions[_id];
        emit PositionClosed(owner, _id);
    }

    // WARNING: This will forfeit all vesting progress and burn any locked oARB
    function emergencyWithdraw(uint256 _id) external {
        VestingPosition memory _position = vestingPositions[_id];
        address owner = ownerOf(_id);
        
        require(owner != address(0), "Owner invalid");
        require(owner == msg.sender, "Invalid position owner");

        uint256 tax = _position.amount * emergencyWithdrawTax / BIPS;

        // Transfer arb back to the user and burn ARB
        oARB.burn(_position.amount);
        // transfer arb to user
        ARB.safeTransfer(owner, _position.amount - tax);
        if (tax > 0) ARB.safeTransfer(treasury, tax);

        promisedArbTokens -= _position.amount;
        _burn(_id);
        delete vestingPositions[_id];
        emit EmergencyWithdraw(owner, _id);
    }

    function retriveTokens(address token, uint256 amount) external onlyConfigurator {
        ERC20(token).safeTransfer(msg.sender, amount);
    }

    // ==================================================================
    // ======================= Admin Functions ==========================
    // ==================================================================

    function ownerSetVestingActive(bool _vestingActive) external onlyConfigurator {
        vestingActive = _vestingActive;
        emit VestingActiveSet(_vestingActive);
    }

    function ownerSetForceCloseActive(bool _forceCloseActive) external onlyConfigurator {
        forceCloseActive = _forceCloseActive;
        emit ForceCloseActiveSet(_forceCloseActive);
    }

    function setPriceFeed(address _priceFeed) external onlyConfigurator {
        require(_priceFeed != address(0), "!pricefeed");
        priceFeed = OracleWrapper(_priceFeed);
        emit SetPriceFeed(_priceFeed);
    }

    function setTreasury(address _treasury) external onlyConfigurator {
        require(_treasury != address(0), "!treasury");
        treasury = _treasury;
        emit SetTreasury(_treasury);
    }

    function setArbVault(address _vault) external onlyConfigurator {
        require(_vault != address(0), "!vault");
        vault = ArbVault(_vault);
        emit SetArbVault(_vault);
    }

    function ownerSetOARB(address _oARB) external onlyConfigurator {
        require(promisedArbTokens == 0, "Outstanding vesting positions");
        oARB = OARB(_oARB);
        emit OARBSet(_oARB);
    }

    function setDurations(uint256 _minDuration, uint256 _maxDuration) external onlyConfigurator {
        minDuration = _minDuration;
        maxDuration = _maxDuration;
        emit SetDurations(_minDuration, _maxDuration);
    }

    function ownerSetClosePositionWindow(uint256 _closePositionWindow) external onlyConfigurator {
        require(_closePositionWindow >= minDuration, "Invalid close position window");
        closePositionWindow = _closePositionWindow;
        emit ClosePositionWindowSet(_closePositionWindow);
    }

    function ownerSetEmergencyWithdrawTax(uint256 _emergencyWithdrawTax) external onlyConfigurator {
        // @follow-up Do we want to allow the full range?
        require(_emergencyWithdrawTax >= 0 && _emergencyWithdrawTax < BIPS, "Invalid emergency withdrawal tax");
        emergencyWithdrawTax = _emergencyWithdrawTax;
        emit EmergencyWithdrawTaxSet(_emergencyWithdrawTax);
    }

    function ownerSetLiquidatorDiscount(uint256 _liquidatorDiscount) external onlyConfigurator {
        require(_liquidatorDiscount <= 250, "discount too high");
        liquidatorDiscount = _liquidatorDiscount;
        emit SetLiquidatorDiscount(_liquidatorDiscount);
    }

    function tokenURI(uint256 id) public view override returns (string memory _uri) { }

    function getBuyPrice(uint256 _id) external view returns (uint256) {
        VestingPosition memory _position = vestingPositions[_id];
        uint256 discount = _calculateDiscount(_position.duration, false);
        uint256 wethPrice = _getTokenPrice(WETH);
        uint256 arbPriceAdj = (_getTokenPrice(address(ARB)) * discount) / BIPS;
        uint256 arbValue = _position.amount * arbPriceAdj;
        return (arbValue / wethPrice) + 1;
    }

    // ==================================================================
    // ======================= Internal Functions =======================
    // ==================================================================

    function _getTokenPrice(address token) internal view returns (uint256) {
        return priceFeed.getChainlinkPrice(token);
    }

    function _calculateDiscount(uint256 _duration, bool _isLiquidator) internal view returns (uint256) {
        return _isLiquidator ? (BIPS - liquidatorDiscount) : BIPS - ((250 * _duration) / 1 weeks);
    }
}

