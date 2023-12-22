

import "./console.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

import { IYieldSlice } from "./IYieldSlice.sol";
import { IYieldSource } from "./IYieldSource.sol";
import { IDiscounter } from "./IDiscounter.sol";
import { YieldData } from "./YieldData.sol";
import { NPVToken } from "./NPVToken.sol";

contract YieldSlice is ReentrancyGuard {
    using SafeERC20 for IERC20;

    event NewDebtSlice(address indexed owner, uint256 indexed id, uint256 tokens, uint256 yield, uint256 npv, uint256 fees);
    event NewCreditSlice(address indexed owner, uint256 indexed id, uint256 npv, uint256 fees);
    event UnlockDebtSlice(address indexed owner, uint256 indexed id);
    event PayDebt(uint256 indexed id, uint256 amount);
    event ReceiveNPV(address indexed recipient, uint256 indexed id, uint256 amount);
    event Claimed(uint256 indexed id, uint256 amount);

    uint256 public constant DISCOUNT_PERIOD = 7 days;

    uint256 public constant FEE_DENOM = 100_0;

    // Max fees limit what can be set by governance. Actual fee may be lower.

    // -- Debt fees -- //
    // Debt fees are a percent of the difference between nominal yield
    // sold, and the net present value. This results in low borrowing
    // cost for short term debt.
    uint256 public constant MAX_DEBT_FEE = 50_0;

    // -- Credit fees -- //
    // Credit fees are are simple percent of the NPV tokens being purchased.
    uint256 public constant MAX_CREDIT_FEE = 20_0;

    address public gov;
    address public treasury;

    uint256 public nextId = 1;
    uint256 public totalShares;
    uint256 public harvestedYield;
    uint256 public dustLimit;
    uint256 public cumulativePaidYield;
    uint256 public activeNPV;

    uint256 public debtFee;
    uint256 public creditFee;

    NPVToken public npvToken;
    IERC20 public immutable generatorToken;
    IERC20 public immutable yieldToken;

    IYieldSource public immutable yieldSource;
    IDiscounter public immutable discounter;
    YieldData public immutable debtData;
    YieldData public immutable creditData;

    struct DebtSlice {
        address owner;
        uint128 createdBlockTimestamp;
        uint128 unlockedBlockTimestamp;
        uint256 shares;
        uint256 tokens;  // TODO: redundant with shares?
        uint256 npv;
        bytes memo;
    }
    mapping(uint256 => DebtSlice) public debtSlices;

    struct CreditSlice {
        address owner;
        uint128 blockTimestamp;
        uint256 npv;
        uint256 claimed;
        bytes memo;
    }
    mapping(uint256 => CreditSlice) public creditSlices;

    modifier onlyGov() {
        require(msg.sender == gov, "YS: gov only");
        _;
    }

    constructor(string memory symbol,
                address yieldSource_,
                address debtData_,
                address creditData_,
                address discounter_,
                uint256 dustLimit_) {
        gov = msg.sender;
        treasury = msg.sender;

        npvToken = new NPVToken(symbol, symbol);
        yieldSource = IYieldSource(yieldSource_);
        generatorToken = IYieldSource(yieldSource_).generatorToken();
        yieldToken = IYieldSource(yieldSource_).yieldToken();
        discounter = IDiscounter(discounter_);
        dustLimit = dustLimit_;
        debtData = YieldData(debtData_);
        creditData = YieldData(creditData_);
    }

    function _min(uint256 x1, uint256 x2) private pure returns (uint256) {
        return x1 < x2 ? x1 : x2;
    }

    function setGov(address gov_) external onlyGov {
        gov = gov_;
    }

    function setTreasury(address treasury_) external onlyGov {
        treasury = treasury_;
    }

    function setDustLimit(uint256 dustLimit_) external onlyGov {
        dustLimit = dustLimit_;
    }

    function setDebtFee(uint256 debtFee_) external onlyGov {
        require(debtFee_ <= MAX_DEBT_FEE, "YS: max debt fee");
        debtFee = debtFee_;
    }

    function setCreditFee(uint256 creditFee_) external onlyGov {
        require(creditFee_ <= MAX_CREDIT_FEE, "YS: max credit fee");
        creditFee = creditFee_;
    }

    function totalTokens() public view returns (uint256) {
        return yieldSource.amountGenerator();
    }

    function cumulativeYield() public view returns (uint256) {
        return harvestedYield + yieldSource.amountPending();
    }

    function cumulativeYieldCredit() public view returns (uint256) {
        return harvestedYield + cumulativePaidYield + yieldSource.amountPending();
    }

    function harvest() external nonReentrant {
        _harvest();
    }

    function _harvest() private {
        uint256 pending = yieldSource.amountPending();
        if (pending == 0) return;
        yieldSource.harvest();
        harvestedYield += pending;
    }

    function recordData() public nonReentrant {
        _recordData();
    }

    function _recordData() private {
        debtData.record(totalTokens(), cumulativeYield());
        creditData.record(npvToken.totalSupply(), cumulativeYieldCredit());
    }

    function tokens(uint256 id) public view returns (uint256) {
        if (totalShares == 0) return 0;
        return totalTokens() * debtSlices[id].shares / totalShares;
    }

    function _previewDebtSlice(uint256 tokens_, uint256 yield) internal view returns (uint256, uint256) {
        uint256 npv = discounter.discounted(tokens_, yield);
        uint256 fees = ((yield - npv) * debtFee) / FEE_DENOM;
        return (npv, fees);
    }

    function previewDebtSlice(uint256 tokens_, uint256 yield) public view returns (uint256, uint256) {
        return _previewDebtSlice(tokens_, yield);
    }

    function debtSlice(address owner,
                       address recipient,
                       uint256 tokens_,
                       uint256 yield,
                       bytes calldata memo) external nonReentrant returns (uint256) {

        require(tokens_ > dustLimit, "YS: dust");

        uint256 newTotalShares;
        uint256 delta;
        uint256 oldTotalTokens = totalTokens();
        if (totalShares == 0 || oldTotalTokens == 0) {
            newTotalShares = tokens_;
            delta = tokens_;
        } else {
            newTotalShares = (oldTotalTokens + tokens_) * totalShares / oldTotalTokens;
            delta = newTotalShares - totalShares;
        }

        generatorToken.safeTransferFrom(msg.sender, address(this), tokens_);
        generatorToken.safeApprove(address(yieldSource), 0);
        generatorToken.safeApprove(address(yieldSource), tokens_);

        yieldSource.deposit(tokens_, false);

        (uint256 npv, uint256 fees) = _previewDebtSlice(tokens_, yield);

        uint256 id = nextId++;
        DebtSlice memory slice = DebtSlice({
            owner: owner,
            createdBlockTimestamp: uint128(block.timestamp),
            unlockedBlockTimestamp: 0,
            shares: delta,
            tokens: tokens_,
            npv: npv,
            memo: memo });
        debtSlices[id] = slice;

        totalShares = newTotalShares;
        npvToken.mint(recipient, npv - fees);
        npvToken.mint(treasury, fees);
        activeNPV += npv;

        _recordData();

        emit NewDebtSlice(owner, id, tokens_, yield, npv, fees);
        
        return id;
    }

    function mintFromYield(address recipient, uint256 amount) external {
        IERC20(yieldToken).safeTransferFrom(msg.sender, address(this), amount);
        npvToken.mint(recipient, amount);
        cumulativePaidYield += amount;
        _recordData();
    }

    function payDebt(uint256 id, uint256 amount) external nonReentrant returns (uint256) {
        require(id < nextId, "YS: invalid id");
        DebtSlice storage slice = debtSlices[id];
        require(slice.unlockedBlockTimestamp == 0, "YS: already unlocked");

        ( , uint256 npv, ) = generated(id);
        uint256 left = npv > slice.npv ? 0 : slice.npv - npv;
        uint256 actual = _min(left, amount);
        IERC20(npvToken).safeTransferFrom(msg.sender, address(this), actual);
        npvToken.burn(address(this), actual);
        slice.npv -= actual;
        activeNPV -= actual;

        emit PayDebt(id, amount);

        return actual;
    }

    function transferOwnership(uint256 id, address who) external nonReentrant {
        require(id < nextId, "YS: invalid id");

        if (debtSlices[id].owner != address(0)) {
            DebtSlice storage slice = debtSlices[id];
            require(slice.owner == msg.sender, "YS: only debt slice owner");
            slice.owner = who;
        } else {
            assert(creditSlices[id].owner != address(0));
            CreditSlice storage slice = creditSlices[id];
            require(slice.owner == msg.sender, "YS: only credit slice owner");
            _claim(id);
            slice.owner = who;
        }
    }

    function unlockDebtSlice(uint256 id) external nonReentrant {
        DebtSlice storage slice = debtSlices[id];
        require(slice.owner == msg.sender, "YS: only owner");
        require(slice.unlockedBlockTimestamp == 0, "YS: already unlocked");

        (, uint256 npv, uint256 refund) = generated(id);
        require(npv >= slice.npv, "YS: npv debt");

        if (refund > 0) {
            _harvest();
            uint256 balance = IERC20(yieldToken).balanceOf(address(this));
            IERC20(yieldToken).safeTransfer(slice.owner, _min(balance, refund));
        }
        uint256 amount = tokens(id);
        yieldSource.withdraw(amount, false, slice.owner);
        slice.unlockedBlockTimestamp = uint128(block.timestamp);
        activeNPV -= slice.npv;

        emit UnlockDebtSlice(slice.owner, id);
    }

    function _creditFeesForNPV(uint256 npv) internal view returns (uint256) {
        return (npv * creditFee) / FEE_DENOM;
    }

    function creditFeesForNPV(uint256 npv) external view returns (uint256) {
        return _creditFeesForNPV(npv);
    }

    function creditSlice(uint256 npv, address who, bytes calldata memo) external returns (uint256) {
        IERC20(npvToken).safeTransferFrom(msg.sender, address(this), npv);

        uint256 fees = _creditFeesForNPV(npv);
        IERC20(npvToken).safeTransfer(treasury, fees);

        uint256 id = nextId++;
        CreditSlice memory slice = CreditSlice({
            owner: who,
            blockTimestamp: uint128(block.timestamp),
            npv: npv - fees,
            claimed: 0,
            memo: memo });
        creditSlices[id] = slice;

        emit NewCreditSlice(who, id, npv, fees);

        return id;
    }

    function _claim(uint256 id) internal returns (uint256) {
        CreditSlice storage slice = creditSlices[id];
        ( , uint256 npv, uint256 claimable) = generatedCredit(id);

        if (claimable == 0) return 0;

        _harvest();
        uint256 amount = _min(claimable, yieldToken.balanceOf(address(this)));
        yieldToken.safeTransfer(slice.owner, amount);
        slice.claimed += amount;

        if (npv == slice.npv) {
            npvToken.burn(address(this), slice.npv);
        }

        emit Claimed(id, amount);

        return amount;
    }

    function claim(uint256 id) external nonReentrant returns (uint256) {
        require(creditSlices[id].owner == msg.sender, "YS: only slice owner");
        return _claim(id);
    }

    function receiveNPV(uint256 id,
                        address recipient,
                        uint256 amount) external nonReentrant {
        CreditSlice storage slice = creditSlices[id];
        require(slice.owner == msg.sender, "YS: only slice owner");
        ( , uint256 npv, ) = generatedCredit(id);
        uint256 available = slice.npv - npv;
        if (amount == 0) {
            amount = available;
        }
        require(amount <= available, "YS: insufficient NPV");
        npvToken.transfer(recipient, amount);
        slice.npv -= amount;

        emit ReceiveNPV(recipient, id, amount);
    }

    function remaining(uint256 id) public view returns (uint256) {
        ( , uint256 npv, ) = generated(id);
        return debtSlices[id].npv - npv;
    }

    function generated(uint256 id) public view returns (uint256, uint256, uint256) {
        DebtSlice storage slice = debtSlices[id];
        uint256 nominal = 0;
        uint256 npv = 0;
        uint256 refund = 0;
        uint256 last = slice.unlockedBlockTimestamp == 0 ? block.timestamp : slice.unlockedBlockTimestamp;

        for (uint256 i = slice.createdBlockTimestamp; i < last; i += DISCOUNT_PERIOD) {
            uint256 end = _min(last - 1, i + DISCOUNT_PERIOD);
            uint256 yts = debtData.yieldPerTokenPerSecond(uint128(i),
                                                          uint128(end),
                                                          totalTokens(),
                                                          cumulativeYield());

            uint256 yield = (yts * (end - i) * slice.tokens) / debtData.PRECISION_FACTOR();
            uint256 estimatedDays = (end - slice.createdBlockTimestamp) / 1 days;
            uint256 pv = discounter.pv(estimatedDays, yield);

            if (npv == slice.npv) {
                refund += yield;
            } else if (npv + pv > slice.npv) {
                uint256 owed = discounter.nominal(estimatedDays, slice.npv - npv);
                uint256 leftover = yield - owed;
                nominal += owed;
                refund += leftover;
                npv = slice.npv;
            } else {
                npv += pv;
                nominal += yield;
            }
        }

        return (nominal, npv, refund);
    }
        
    function generatedCredit(uint256 id) public view returns (uint256, uint256, uint256) {
        CreditSlice storage slice = creditSlices[id];
        uint256 nominal = 0;
        uint256 npv = 0;
        uint256 claimable = 0;

        for (uint256 i = slice.blockTimestamp; npv < slice.npv && i < block.timestamp; i += DISCOUNT_PERIOD) {
            uint256 end = _min(block.timestamp - 1, i + DISCOUNT_PERIOD);
            uint256 yts = creditData.yieldPerTokenPerSecond(uint128(i),
                                                            uint128(end),
                                                            activeNPV,
                                                            cumulativeYieldCredit());

            uint256 yield = (yts * (end - i) * slice.npv) / creditData.PRECISION_FACTOR();
            uint256 estimatedDays = (end - slice.blockTimestamp) / 1 days;
            uint256 pv = discounter.pv(estimatedDays, yield);

            if (npv + pv > slice.npv) {
                pv = slice.npv - npv;
                yield = discounter.nominal(estimatedDays, pv);
            }

            claimable += yield;
            nominal += yield;
            npv += pv;
        }

        return (nominal, npv, claimable - slice.claimed);
    }
}

