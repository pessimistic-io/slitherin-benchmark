// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {Initializable} from "./Initializable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {IPool} from "./IPool.sol";
import {IBurnableERC20} from "./IBurnableERC20.sol";
import {IPreLevelConverter} from "./IPreLevelConverter.sol";
import {PairOracleTWAP, PairOracle} from "./PairOracleTWAP.sol";
import {FixedPoint} from "./FixedPoint.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";

contract PreLevelConverter is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IPreLevelConverter {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;
    using PairOracleTWAP for PairOracle;

    /// @notice shared PRECISON for TWAP and taxRate
    uint256 public constant PRECISION = 1e6;
    uint256 public constant TWAP_DURATION = 1 days;
    uint256 public constant TWAP_UPDATE_TIMEOUT = 5 minutes;
    uint256 public constant ALLOWED_TWAP_DEVIATION = 0.05e6; // allow 5% deviation

    // solhint-disable-next-line var-name-mixedcase
    IERC20 public LVL;
    // solhint-disable-next-line var-name-mixedcase
    IBurnableERC20 public preLVL;
    // solhint-disable-next-line var-name-mixedcase
    IERC20Metadata public USDT;

    uint256 public taxRate;
    /// @notice only this sender can report LVL/USDT TWAP
    address public priceReporter;
    /// @notice LVL/USDT TWAP
    uint256 public twap;
    uint256 public twapTimestamp;
    /// @notice factor to convert USDT amount to LVL amount, based on their decimals. Eg, if USDT decimals is 6, LVL decimals is 18, then this value is 10 ^ 12
    uint256 public missingDecimal;
    address public daoTreasury;
    IPool public pool;
    /// @notice list of tranche to convert tax to
    IBurnableERC20[] public llpTokens;
    /// @notice pair oracle used to verify posted TWAP
    PairOracle public lvlUsdtTwapOracle;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _lvl,
        address _preLvl,
        address _usdt,
        address _daoTreasury,
        address _pool,
        address _lvlUsdtUniV2Pair,
        uint256 _taxRate,
        uint256 _missingDecimal,
        IBurnableERC20[] calldata _llpTokens
    ) external initializer {
        if (_lvl == address(0)) revert ZeroAddress();
        if (_preLvl == address(0)) revert ZeroAddress();
        if (_usdt == address(0)) revert ZeroAddress();
        if (_daoTreasury == address(0)) revert ZeroAddress();
        if (_pool == address(0)) revert ZeroAddress();
        if (_llpTokens.length == 0) revert TrancheListIsEmpty();

        __ReentrancyGuard_init();
        __Ownable_init();

        LVL = IERC20(_lvl);
        preLVL = IBurnableERC20(_preLvl);
        USDT = IERC20Metadata(_usdt);
        daoTreasury = _daoTreasury;
        pool = IPool(_pool);

        for (uint256 i = 0; i < _llpTokens.length; i++) {
            address llpToken = address(_llpTokens[i]);
            if (!pool.isTranche(llpToken)) revert InvalidLLPAddress();
        }
        llpTokens = _llpTokens;
        taxRate = _taxRate;
        missingDecimal = 10 ** _missingDecimal;
        _configLvlUsdtPairOracle(_lvlUsdtUniV2Pair);
    }

    function convert(uint256 _preLvlAmount, uint256 _maxTaxAmount, address _to, uint256 _deadline)
        external
        nonReentrant
    {
        if (block.timestamp > _deadline) revert Timeout();
        if (twap == 0) revert TWAPNotAvailable();
        if (block.timestamp > twapTimestamp + TWAP_DURATION) revert TWAPOutdated();

        uint256 taxAmount = _preLvlAmount * twap * taxRate / PRECISION / PRECISION / missingDecimal;
        if (taxAmount > _maxTaxAmount) revert SlippageExceeded(taxAmount, _maxTaxAmount);

        // given that USDT is not a deflationary token, we use tax amount as
        USDT.safeTransferFrom(msg.sender, address(this), taxAmount);
        uint256 taxAmountToPool = taxAmount / 2;
        _sendToLiquidityPool(taxAmountToPool);
        // send the rest to dao, including dust
        USDT.safeTransfer(daoTreasury, USDT.balanceOf(address(this)));

        preLVL.burnFrom(msg.sender, _preLvlAmount);
        LVL.safeTransfer(_to, _preLvlAmount);
        emit Converted(msg.sender, _preLvlAmount, taxAmountToPool, taxAmount - taxAmountToPool);
    }

    function updateTWAP(uint256 _twap, uint256 _timestamp) external {
        if (msg.sender != priceReporter) revert Unauthorized();
        _verifyTwap(_twap, _timestamp);

        twap = _twap;
        twapTimestamp = _timestamp;
        emit TWAPUpdated(_twap, _timestamp);
    }

    function getReferenceTWAP() external view returns (uint256) {
        return lvlUsdtTwapOracle.currentTWAP() * PRECISION / (10 ** USDT.decimals());
    }

    // =========== RESTRICTED FUNCTIONS ============
    function setPriceReporter(address _reporter) external onlyOwner {
        if (_reporter == address(0)) revert ZeroAddress();
        if (priceReporter != _reporter) {
            priceReporter = _reporter;
            emit PriceReporterSet(_reporter);
        }
    }

    function configLvlUsdtPairOracle(address _uniswapv2PairAddress) external onlyOwner {
        _configLvlUsdtPairOracle(_uniswapv2PairAddress);
    }

    // =========== INTERNAL FUNCTIONS ============
    /**
     * @notice config guard oracle
     * @param _uniswapv2PairAddress UniswapV2 compatible LP address
     */
    function _configLvlUsdtPairOracle(address _uniswapv2PairAddress) internal {
        if (_uniswapv2PairAddress == address(0)) revert ZeroAddress();

        lvlUsdtTwapOracle = PairOracle({
            pair: IUniswapV2Pair(_uniswapv2PairAddress),
            token: address(LVL),
            priceAverage: FixedPoint.uq112x112(0),
            lastBlockTimestamp: 0,
            priceCumulativeLast: 0,
            lastTWAP: 0
        });

        lvlUsdtTwapOracle.update();
    }

    function _sendToLiquidityPool(uint256 _amount) internal {
        for (uint256 i = 0; i < llpTokens.length;) {
            IBurnableERC20 llp = llpTokens[i];
            uint256 usdtAmount = _amount / llpTokens.length; // rely on config setter

            USDT.safeIncreaseAllowance(address(pool), usdtAmount);
            pool.addLiquidity(address(llp), address(USDT), usdtAmount, 0, address(this));
            // burn all, event dust or LP transfered by incident
            llp.burn(llp.balanceOf(address(this)));

            unchecked {
                ++i;
            }
        }
    }

    function _verifyTwap(uint256 _keeperTwap, uint256 _keeperTimestamp) internal {
        if (block.timestamp > _keeperTimestamp + TWAP_UPDATE_TIMEOUT) revert TwapUpdateTimeout();
        lvlUsdtTwapOracle.update();

        // pairOracle return the cost of buying 1 LVL in USDT, so we round it to our preferred PRECISION
        uint256 guardPrice = lvlUsdtTwapOracle.lastTWAP * PRECISION / (10 ** USDT.decimals());
        uint256 precisedKeeperTwap = _keeperTwap * PRECISION;

        if (
            precisedKeeperTwap < guardPrice * (PRECISION - ALLOWED_TWAP_DEVIATION)
                || precisedKeeperTwap > guardPrice * (PRECISION + ALLOWED_TWAP_DEVIATION)
        ) {
            revert TwapRejected();
        }
    }
}

