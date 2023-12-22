// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

// Abstract Classes
import {UpgradeableOperableKeepable} from "./UpgradeableOperableKeepable.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {ERC1155TokenReceiver} from "./ERC1155.sol";
import {IOptionStrategy} from "./IOptionStrategy.sol";
import {IOption} from "./IOption.sol";
import {ICompoundStrategy} from "./ICompoundStrategy.sol";
import {IRouter} from "./IRouter.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {ISeaport} from "./ISeaport.sol";
import {IValorem} from "./IValorem.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
//Libraries
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {AssetsPricing} from "./AssetsPricing.sol";

contract ValoremAdapter is IOption, ERC1155TokenReceiver, UpgradeableOperableKeepable {
    using FixedPointMathLib for uint256;

    // Info needed execute options (stack too deep)
    struct ExecuteInfo {
        address thisAddress;
        uint256 wethAmount;
        uint256 totalCollateral;
        uint256 id;
        uint8 decimals;
        ISeaport.FullFillOrder seaportOrder;
    }

    struct FlashCallbackData {
        uint256 optionId;
        uint256 amount;
        uint256 cost;
        address caller;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  VARIABLES                                 */
    /* -------------------------------------------------------------------------- */
    /// @notice Internal representation of 100%
    uint256 private constant BASIS_POINTS = 1e12;

    // @notice Tokens used in the underlying logic
    IERC20 private constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 private constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    /// @notice hash(epoch, type, strike) => id
    mapping(bytes32 => uint256) public optionId;

    /// @notice hash(epoch, type, strike) => decimals
    mapping(bytes32 => uint256) public optionDecimals;

    /// @notice Metavaults Factory
    address public factory;

    /// @notice Seaport 1.5
    ISeaport public seaport;

    /// @notice Valorem Clearing House 1.0.1 (on october 4th)
    IValorem public valorem;

    /// @notice ETH-USDC V3 Pool
    IUniswapV3Pool public WETH_USDC_V3;

    uint256 public constant VALOREM_BPS = 10_000;

    /// @notice Slippage to avoid reverts after simulations
    uint256 private slippage;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Initializes the transparent proxy of the Valorem Adapter
     * @param _factory address of the factory
     * @param _seaport 1.5 seaport address
     */
    function initializeOptionAdapter(address _factory, address _seaport, address _valorem) external initializer {
        __Governable_init(msg.sender);

        if (_seaport == address(0) || _factory == address(0)) {
            revert ZeroAddress();
        }

        // Store factory in storage
        factory = _factory;

        // Store seaport in storage
        seaport = ISeaport(_seaport);

        // Store valorem in storage
        valorem = IValorem(_valorem);

        // Flash loan pool
        WETH_USDC_V3 = IUniswapV3Pool(0x17c14D2c404D167802b16C450d3c99F88F2c4F4d); // 3000 fee

        slippage = (99 * 1e12) / 100;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY OPERATOR                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Buy options.
     * @param params Parameter needed to buy options.
     */
    function purchase(OptionParams calldata params) public onlyOperator {
        ExecuteInfo memory info;

        info.thisAddress = address(this);

        info.wethAmount = WETH.balanceOf(info.thisAddress);

        WETH.approve(address(IOptionStrategy(msg.sender).swapper()), info.wethAmount);

        // Swaps received WETH to USDC
        IOptionStrategy(msg.sender).swapper().swapWethToUSDC(info.wethAmount);

        // Gets total collateral we have
        info.totalCollateral = USDC.balanceOf(info.thisAddress);

        (info.id, info.decimals, info.seaportOrder) =
            abi.decode(params._optionData, (uint256, uint8, ISeaport.FullFillOrder));

        if (info.totalCollateral < params._option.cost) {
            revert NotEnoughCollateral();
        }

        // Approve for spending on Seaport
        USDC.approve(address(seaport), params._option.cost);

        if (!seaport.fulfillOrder(info.seaportOrder.order, info.seaportOrder.fulfillerConduitKey)) {
            revert FulfillOrderFail();
        }

        // Add  the bought strike data to the storage of Option Strategy in order to handle mid epoch deposits
        IOptionStrategy(msg.sender).addBoughtStrikes(params._epoch, params._option.type_, params._option);

        bytes32 optionHash = keccak256(abi.encode(params._epoch, params._option.type_, params._option.strike));

        optionId[optionHash] = info.id;
        optionDecimals[optionHash] = info.decimals;

        // Emit event showing the prices of the strikes we bought and other relevant info
        emit ValoremPurchase(
            params._epoch, params._option.strike, params._option.cost, params._option.amount, params._option.type_
        );
    }

    /**
     * @notice Exercise ITM options.
     * @param params OptionParams struct containing the option data.
     */

    function settle(OptionParams calldata params) public onlyOperator returns (uint256) {
        uint256 _optionId = optionId[keccak256(abi.encode(params._epoch, params._option.type_, params._option.strike))];

        // Option Data
        IValorem.Option memory valoremOption = valorem.option(_optionId);

        uint256 _cost = _exerciseCost(valoremOption, params._option.amount);

        if (params._option.type_ == IRouter.OptionStrategy.BULL) {
            WETH_USDC_V3.flash(
                address(this),
                0,
                _cost,
                abi.encode(
                    FlashCallbackData({
                        optionId: _optionId,
                        amount: params._option.amount,
                        cost: _cost,
                        caller: msg.sender
                    })
                )
            );
        } else {
            WETH_USDC_V3.flash(
                address(this),
                _cost,
                0,
                abi.encode(
                    FlashCallbackData({
                        optionId: _optionId,
                        amount: params._option.amount,
                        cost: _cost,
                        caller: msg.sender
                    })
                )
            );
        }

        return 0;
    }

    /// @dev After we take the flash loan, Uniswap calls this fallback function
    /// Flash-loaning assets incur a 0.05% fee
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external {
        if (msg.sender != address(WETH_USDC_V3)) {
            revert CallerIsNotAllowed();
        }

        (FlashCallbackData memory _data) = abi.decode(data, (FlashCallbackData));
        // Now we have the needed assets to settle, so we can exercise the options and using profits to pay back the flash loan + fees
        IRouter.OptionStrategy _type;

        // On puts we borrow WETH
        if (fee0 > 0) {
            WETH.approve(address(valorem), _data.cost);
            valorem.exercise(_data.optionId, uint112(_data.amount));

            uint256 toPayBack = fee0 + _data.cost;
            uint256 currentWETH = WETH.balanceOf(address(this));
            if (currentWETH < toPayBack) {
                // currentUSDC < toPayBack
                uint256 usdcNeeded = IOptionStrategy(_data.caller).swapper().wethFromUSDCIn(toPayBack - currentWETH); // toPayBack - currentWETH
                if (usdcNeeded > 0) {
                    USDC.approve(address(IOptionStrategy(_data.caller).swapper()), usdcNeeded);
                    IOptionStrategy(_data.caller).swapper().swapUSDCToWeth(usdcNeeded);
                }
            }

            WETH.transfer(msg.sender, fee0 + _data.cost);

            _type = IRouter.OptionStrategy.BEAR;
        }
        // On calls we borrow USDC
        else {
            USDC.approve(address(valorem), _data.cost);
            valorem.exercise(_data.optionId, uint112(_data.amount));

            // payback swap weth rewards to get fee1 + _data.cost USDC
            uint256 toPayBack = fee1 + _data.cost;
            uint256 currentUSDC = USDC.balanceOf(address(this));
            if (currentUSDC < toPayBack) {
                // currentUSDC < toPayBack
                uint256 wethNeeded = IOptionStrategy(_data.caller).swapper().USDCFromWethIn(toPayBack - currentUSDC); // toPayBack - currentUSDC
                if (wethNeeded > 0) {
                    WETH.approve(address(IOptionStrategy(_data.caller).swapper()), wethNeeded);
                    IOptionStrategy(_data.caller).swapper().swapWethToUSDC(wethNeeded);
                }
            }
            USDC.transfer(msg.sender, toPayBack);

            _type = IRouter.OptionStrategy.BULL;
        }

        uint256 usdcBalance = USDC.balanceOf(address(this));

        // If flow reached here, means that we have succesfully exercised the options profitably and paid back the flash loan
        if (usdcBalance > 0) {
            USDC.approve(address(IOptionStrategy(_data.caller).swapper()), usdcBalance);
            IOptionStrategy(_data.caller).swapper().swapUSDCToWeth(usdcBalance);
        }
        uint256 wethAmount = WETH.balanceOf(address(this));

        if (wethAmount > 0) {
            // Transfer to Option Strategy
            WETH.transfer(_data.caller, WETH.balanceOf(address(this)));
            IOptionStrategy(_data.caller).afterSettleOptions(_type, wethAmount);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                     VIEW                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Gets PNL and convert to WETH if > 0
     */
    function position(address _optionStrategy, address _compoundStrategy, IRouter.OptionStrategy _type)
        external
        view
        returns (uint256)
    {
        (uint256 pnl_, uint256 cost_) = _pnl(_optionStrategy, _compoundStrategy, _type);

        // Calculate min amoutn out of sushi trade. This takes in consideration fees
        cost_ = IOptionStrategy(_optionStrategy).swapper().RawUSDCToWETH(cost_);
        if (pnl_ > cost_) {
            return pnl_ - cost_;
        }
        return 0;
    }

    // Simulate outcome of the bought options if we were exercising now
    function pnl(address _optionStrategy, address _compoundStrategy, IRouter.OptionStrategy _type)
        external
        view
        returns (uint256)
    {
        (uint256 pnl_,) = _pnl(_optionStrategy, _compoundStrategy, _type);
        return pnl_;
    }

    function lpToCollateral(address _lp, uint256 _amount, address _optionStrategy) external view returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(_lp);

        // Very precise but not 100%
        (uint256 token0Amount, uint256 token1Amount) = AssetsPricing.breakFromLiquidityAmount(_lp, _amount);

        uint256 wethAmount;

        // Convert received tokens from LP to WETH.
        // This function gets maxAmountOut and accounts for slippage + fees
        // We dont support LPs that doesnt have WETH in its composition (for now)
        if (pair.token0() == address(WETH)) {
            wethAmount =
                token0Amount + IOptionStrategy(_optionStrategy).swapper().wethFromToken(pair.token1(), token1Amount);
        } else if (pair.token1() == address(WETH)) {
            wethAmount =
                token1Amount + IOptionStrategy(_optionStrategy).swapper().wethFromToken(pair.token0(), token0Amount);
        } else {
            revert NoSupport();
        }

        return IOptionStrategy(_optionStrategy).swapper().USDCFromWeth(wethAmount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  ONLY FACTORY                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Add Operator role to _newOperator.
     */
    function addOperator(address _newOperator) public override {
        if (!(hasRole(OPERATOR, msg.sender) || (msg.sender == factory))) {
            revert CallerIsNotAllowed();
        }

        _grantRole(OPERATOR, _newOperator);

        emit OperatorAdded(_newOperator);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY GOVERNOR                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Moves assets from the strategy to `_to`
     * @param _assets An array of IERC20 compatible tokens to move out from the strategy
     * @param _withdrawNative `true` if we want to move the native asset from the strategy
     */
    function emergencyWithdraw(address _to, address[] memory _assets, bool _withdrawNative) external onlyGovernor {
        uint256 assetsLength = _assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = IERC20(_assets[i]);
            uint256 assetBalance = asset.balanceOf(address(this));

            if (assetBalance > 0) {
                // Transfer the ERC20 tokens
                asset.transfer(_to, assetBalance);
            }

            unchecked {
                ++i;
            }
        }

        uint256 nativeBalance = address(this).balance;

        // Nothing else to do
        if (_withdrawNative && nativeBalance > 0) {
            // Transfer the native currency
            (bool sent,) = payable(_to).call{value: nativeBalance}("");
            if (!sent) {
                revert FailSendETH();
            }
        }

        emit EmergencyWithdrawal(msg.sender, _to, _assets, _withdrawNative ? nativeBalance : 0);
    }

    /**
     * @notice Update Factory
     * @param _factory Fatory address
     */
    function updateFactory(address _factory) external onlyGovernor {
        factory = _factory;
    }

    /**
     * @notice Update Valorem
     * @param _valorem Valore address
     */
    function updateValorem(address _valorem) external onlyGovernor {
        valorem = IValorem(_valorem);
    }

    /**
     * @notice Update Seaport
     * @param _seaport Seaport address
     */
    function updateSeaport(address _seaport) external onlyGovernor {
        seaport = ISeaport(_seaport);
    }

    /**
     * @notice Update Flash loan pool
     * @param _pool flash loan pool address
     */
    function updateflashPool(address _pool) external onlyGovernor {
        WETH_USDC_V3 = IUniswapV3Pool(_pool);
    }

    /**
     * @notice Default slippage for safety measures
     * @param _slippage Default slippage
     */
    function setSlippage(uint256 _slippage) external onlyGovernor {
        if (_slippage == 0 || _slippage > BASIS_POINTS) revert InvalidSlippage();

        slippage = _slippage;
    }

    /* -------------------------------------------------------------------------- */
    /*                                     PRIVATE                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice return current option pnl and cost
     * @return pnl_ in usd in 6 decimals
     * @return totalCost_ total amount paid to purchased these options
     */
    function _pnl(address _optionStrategy, address _compoundStrategy, IRouter.OptionStrategy _type)
        private
        view
        returns (uint256 pnl_, uint256 totalCost_)
    {
        uint16 systemEpoch = ICompoundStrategy(_compoundStrategy).currentEpoch();

        IOptionStrategy.Option[] memory _options =
            IOptionStrategy(_optionStrategy).getOptions(systemEpoch, address(this), _type);

        uint256 length = _options.length;

        // Check PNL checking individually PNL on each strike we bought
        for (uint256 i; i < length;) {
            if (_options[i].amount > 0) {
                // Get Option ID
                uint256 _optionId = optionId[keccak256(abi.encode(systemEpoch, _options[i].type_, _options[i].strike))];
                // Option Data
                IValorem.Option memory valoremOption = valorem.option(_optionId);
                if (
                    block.timestamp >= valoremOption.exerciseTimestamp
                        && block.timestamp < valoremOption.expiryTimestamp
                ) {
                    uint256 expectedUnderlying = valoremOption.underlyingAmount * _options[i].amount;

                    if (_type == IRouter.OptionStrategy.BULL) {
                        // RETURN WETH REWARDS, ASK AND PAYBACK USDC TO SETTLE
                        // CALL
                        uint256 exerciseCost = _exerciseCost(valoremOption, _options[i].amount);

                        // add flash pool fee
                        exerciseCost = exerciseCost + exerciseCost.mulDivUp(WETH_USDC_V3.fee(), 1e6);
                        exerciseCost = IOptionStrategy(_optionStrategy).swapper().USDCFromWethIn(exerciseCost); // eth 18 decimals

                        if (expectedUnderlying > exerciseCost) {
                            pnl_ = pnl_ + (expectedUnderlying - exerciseCost); // eth 18 decimals
                        }
                    } else {
                        // PUT
                        // RETURN WETH REWARDS, ASK AND PAYBACK WETH TO SETTLE
                        uint256 exerciseCost = _exerciseCost(valoremOption, _options[i].amount);
                        exerciseCost = IOptionStrategy(_optionStrategy).swapper().wethFromUSDCIn(exerciseCost); // usdc 6 decimals

                        // add flash pool fee
                        exerciseCost = exerciseCost + exerciseCost.mulDivUp(WETH_USDC_V3.fee(), 1e6);

                        if (expectedUnderlying > exerciseCost) {
                            pnl_ = pnl_
                                + IOptionStrategy(_optionStrategy).swapper().wethFromUSDC(expectedUnderlying - exerciseCost); // eth in 18 decimals
                        }
                    }
                }
            }

            totalCost_ = totalCost_ + _options[i].cost; // usdc in 6 decimals

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice return exercise cost for an option
     * @return exercise cost if CALL, is in usdc if PUT is in weth
     */
    function _exerciseCost(IValorem.Option memory option, uint256 amount) private view returns (uint256) {
        // Exercise Amount
        uint256 rxAmount = option.exerciseAmount * amount;
        // Fee
        uint256 fee;
        if (valorem.feesEnabled()) {
            fee = (rxAmount * valorem.feeBps()) / VALOREM_BPS;
            if (fee == 0) {
                fee = 1;
            }
        }

        return rxAmount + fee;
    }

    function _applySlippage(uint256 _amountOut, uint256 _slippage) private pure returns (uint256) {
        return _amountOut.mulDivDown(_slippage, BASIS_POINTS);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event ValoremPurchase(
        uint16 indexed epoch, uint32 strike, uint256 cost, uint256 amount, IRouter.OptionStrategy type_
    );

    event ValoremSettle(
        uint16 indexed epoch,
        uint256 optionId,
        IRouter.OptionStrategy type_,
        uint32 strike,
        uint256 optionAmount,
        uint256 wethAmount
    );

    event EmergencyWithdrawal(address indexed caller, address indexed receiver, address[] tokens, uint256 nativeBalanc);

    /* -------------------------------------------------------------------------- */
    /*                                    ERRORS                                  */
    /* -------------------------------------------------------------------------- */

    error NotEnoughCollateral();
    error FulfillOrderFail();
    error FailSendETH();
    error ZeroAddress();
    error NoSupport();
    error InvalidSlippage();
}

