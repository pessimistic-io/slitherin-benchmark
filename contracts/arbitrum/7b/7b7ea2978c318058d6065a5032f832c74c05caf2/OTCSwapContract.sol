// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import { Ownable } from "./Ownable.sol";
import { SpotMarginAccount } from "./SpotMarginAccount.sol";
import { IERC20 } from "./IERC20.sol";
import { ISubAccount } from "./ISubAccount.sol";
import { ICounterPartyRegistry } from "./ICounterPartyRegistry.sol";
import { ISwapContractManager } from "./ISwapContractManager.sol";

contract OTCSwapContract is Ownable {


    /*///////////////////////////////////////////////////////////////
                        Constants and Immutables
    //////////////////////////////////////////////////////////////*/

    uint8 constant public ACTIVE = 0;
    uint8 constant public CLOSED = 1;

    uint256 public immutable swapIndex;
    address public immutable operator;
    address public immutable swapContractManager;

    uint256 constant private BIPS_DIVISOR = uint256(10000);
    uint256 constant private DECIMAL_DIVISOR = uint256(1000000);
    uint256 constant private DECIMAL_BIPS_DIVISOR = BIPS_DIVISOR * DECIMAL_DIVISOR;

    /*///////////////////////////////////////////////////////////////
                        State Variables
    //////////////////////////////////////////////////////////////*/

    uint8 public state;

    struct SwapContractData {
        uint8 direction;
        uint256 initialUnderlyingPrice;
        uint256 swapContractUnits;
        address underlyingToken;
        address collateralToken;
        address receiverSubAccount;
        address payerSubAccount;
    }

    uint256 public referencePrice;
    uint256 public newUnderlyingPrice;
    uint256 public receiverVariationMarginBips;
    uint256 public payerVariationMarginBips;

    SwapContractData public swapContractData;

    /*///////////////////////////////////////////////////////////////
                        Events
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice This event is triggered when the underlying price is updated.
     * @param underlyingPrice The new underlyingPrice;
     */
    event UpdateUnderlyingPrice(uint256 underlyingPrice);

    /**
     * @notice This event is triggered when the reference price is updated.
     * @param referencePrice The new referencePrice;
     */
    event UpdateReferencePrice(uint256 referencePrice);

    /**
     * @notice This event is triggered when the variation margins are updated.
     * @param newReceiverVariationMarginBips The new receiver variation margin bips.
     * @param newPayerVariationMarginBips The new payer variation margin bips.
     */
    event UpdateVariationMargins(uint256 newReceiverVariationMarginBips, uint256 newPayerVariationMarginBips);

    /**
     * @notice This event is triggered when the notional value is updated
     * @param newInitialUnderlyingPrice The new initial underlying price, calculated offchain.
     * @param newSwapContractUnits The new amount of swap contract units, calculated offchain.
     */
    event UpdateNotionalValue(uint256 newInitialUnderlyingPrice, uint256 newSwapContractUnits);

    /**
     * @notice This event is triggered when current position is closed.
     * @param receiverMarginBips The new receiver variation margin bips.
     * @param payerMarginBips The new payer variation margin bips.
     * @param newUnderlyingPrice The new initial underlying price, calculated offchain.
     */
    event ClosePosition(uint256 receiverMarginBips, uint256 payerMarginBips, uint256 newUnderlyingPrice);

    /**
     * @notice This event is triggered when margin is transferred.
     * @param fromSubAccount The subaccount that transfers margin.
     * @param toSubAccount The subaccount that receives margin.
     * @param token The token that is transferred.
     * @param amount The amount of margin that is transferred.
     */
    event TransferMargin(address fromSubAccount, address toSubAccount, address token, uint256 amount);

    /*///////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor
     * @param _direction The direction of the swap contract. 0 for short, 1 for long.
     * @param _operator The address of the operator.
     * @param _swapContractManager The address of the swap contract manager.
     * @param _underlyingToken The address of the underlying token.
     * @param _collateralToken The collateral token used for the swap contract.
     * @param _receiverSubAccount The receiver sub account address.
     * @param _payerSubAccount The payer sub account address.
     * @param _swapIndex The index of this swap as tracked by the swap contract manager. Used for updating state changes.
     * @param _initialUnderlyingPrice The initial underlying price for the swap contract.
     * @param _swapContractUnits The amount of units for the swap contract.
     * @param _receiverVariationMarginBips The initial margin provided by the receiver.
     * @param _payerVariationMarginBips The intitial margin provided by the payer.
     */

    constructor(
        uint8 _direction,
        address _operator,
        address _swapContractManager,
        address _underlyingToken,
        address _collateralToken,
        address _receiverSubAccount,
        address _payerSubAccount,
        uint256 _swapIndex,
        uint256 _initialUnderlyingPrice,
        uint256 _swapContractUnits,
        uint256 _receiverVariationMarginBips,
        uint256 _payerVariationMarginBips
    ) {
        require(_operator != address(0), '0 address');
        require(_swapContractManager != address(0), '0 address');
        require(_underlyingToken != address(0), '0 address');
        require(_collateralToken != address(0), '0 address');
        require(_receiverSubAccount != address(0), '0 address');
        require(_payerSubAccount != address(0), '0 address');
        require(_initialUnderlyingPrice > 0, '0 amount');
        require(_swapContractUnits > 0, '0 amount');

        operator = _operator;
        swapContractManager = _swapContractManager;

        swapIndex = _swapIndex;

        swapContractData = SwapContractData(
            _direction, 
            _initialUnderlyingPrice, 
            _swapContractUnits,
            _underlyingToken, 
            _collateralToken,
            _receiverSubAccount,
            _payerSubAccount
        );

        receiverVariationMarginBips = _receiverVariationMarginBips;
        payerVariationMarginBips = _payerVariationMarginBips;
        referencePrice = _initialUnderlyingPrice;

        state = ACTIVE;

    }

    /*///////////////////////////////////////////////////////////////
                        Modifiers
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Only called by controller
     */
    modifier onlyOperator() {
        require(msg.sender == operator, "Only Operator");
        _;
    }

    /*///////////////////////////////////////////////////////////////
                            Base Operations
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Partially liquidate the TRS position
     * @param underlyingPrice The new underlying price.
     * @param liquidationUnits The amout of swap units to liquidate.
     */
    function partialLiquidation(uint256 underlyingPrice, uint256 liquidationUnits) external onlyOperator
    {
        uint256 swapUnits = swapContractData.swapContractUnits;
        uint256 liquidationPercent = (liquidationUnits * BIPS_DIVISOR / swapUnits); 
        //set new price
        newUnderlyingPrice = underlyingPrice;
        //emit
        emit UpdateUnderlyingPrice(newUnderlyingPrice);
        //compare new underlying price
        if (newUnderlyingPrice > referencePrice) {
            _liquidatePositionGreater(liquidationPercent);
        } else {
            _liquidatePositionLesser(liquidationPercent);
        }
        //set referencePrice as newUnderlyingPrice after positions updated
        referencePrice = newUnderlyingPrice;
        //update notional value
        updateNotionalValue(swapContractData.initialUnderlyingPrice, swapUnits - liquidationUnits);
    }

    /**
     * @notice Update the margin positions of the receiver and payer if new underlying price greater than initial.
     * @param liquidationPercent The percent of the TRS to be liquidated.
     */
    function _liquidatePositionGreater(uint256 liquidationPercent) private 
    {

        address receiver = swapContractData.receiverSubAccount;
        address payer = swapContractData.payerSubAccount;
        uint256 swapUnits = swapContractData.swapContractUnits;
        uint256 initialUnderlyingPrice = swapContractData.initialUnderlyingPrice;
        uint256 liquidatedUnits = swapUnits * liquidationPercent / BIPS_DIVISOR;
        uint256 markToMarketPnl = ((newUnderlyingPrice - referencePrice) * swapUnits) / DECIMAL_DIVISOR;
        uint256 liquidationPnl;
        uint256 requiredMargin;
        uint256 variationMargin;

        if (swapContractData.direction == 0) {
            requiredMargin = (markToMarketPnl * receiverVariationMarginBips) / BIPS_DIVISOR;
            variationMargin = BIPS_DIVISOR - receiverVariationMarginBips;
            if (newUnderlyingPrice > initialUnderlyingPrice) {
                liquidationPnl = ((newUnderlyingPrice - initialUnderlyingPrice) * liquidatedUnits * variationMargin) / DECIMAL_BIPS_DIVISOR;
                _updateMargins(receiver, payer, requiredMargin + liquidationPnl);
            } else {
                liquidationPnl = ((initialUnderlyingPrice - newUnderlyingPrice) * liquidatedUnits * variationMargin) / DECIMAL_BIPS_DIVISOR;
                _updateMargins(receiver, payer, requiredMargin);
                _updateMargins(payer, receiver, liquidationPnl);
            }
        } else {
            requiredMargin = (markToMarketPnl * payerVariationMarginBips) / BIPS_DIVISOR;
            variationMargin = BIPS_DIVISOR - payerVariationMarginBips;
            if (newUnderlyingPrice > initialUnderlyingPrice) {
                liquidationPnl = ((newUnderlyingPrice - initialUnderlyingPrice) * liquidatedUnits * variationMargin) / DECIMAL_BIPS_DIVISOR;
                _updateMargins(payer, receiver, requiredMargin + liquidationPnl);
            } else {
                liquidationPnl = ((initialUnderlyingPrice - newUnderlyingPrice) * liquidatedUnits * variationMargin) / DECIMAL_BIPS_DIVISOR;
                _updateMargins(payer, receiver, requiredMargin);
                _updateMargins(receiver, payer, liquidationPnl);
            }
        }
    }

    /**
     * @notice Update the margin positions of the receiver and payer if new underlying price less than initial.
     * @param liquidationPercent The percent of the TRS to be liquidated. 
     */
    function _liquidatePositionLesser(uint256 liquidationPercent) private
    {

        address receiver = swapContractData.receiverSubAccount;
        address payer = swapContractData.payerSubAccount;
        uint256 swapUnits = swapContractData.swapContractUnits;
        uint256 initialUnderlyingPrice = swapContractData.initialUnderlyingPrice;
        uint256 liquidatedUnits = swapUnits * liquidationPercent / BIPS_DIVISOR;
        uint256 markToMarketPnl = ((referencePrice - newUnderlyingPrice) * swapUnits) / DECIMAL_DIVISOR;
        uint256 liquidationPnl;
        uint256 requiredMargin;
        uint256 variationMargin;

        if (swapContractData.direction == 0) {
            requiredMargin = (markToMarketPnl * payerVariationMarginBips) / BIPS_DIVISOR;
            variationMargin = BIPS_DIVISOR - payerVariationMarginBips;
            if (initialUnderlyingPrice > newUnderlyingPrice) {
                liquidationPnl = ((initialUnderlyingPrice - newUnderlyingPrice) * liquidatedUnits * variationMargin) / DECIMAL_BIPS_DIVISOR;
                _updateMargins(payer, receiver, requiredMargin + liquidationPnl);
            } else {
                liquidationPnl = ((newUnderlyingPrice - initialUnderlyingPrice) * liquidatedUnits * variationMargin) / DECIMAL_BIPS_DIVISOR;
                _updateMargins(payer, receiver, requiredMargin);
                _updateMargins(receiver, payer, liquidationPnl);
            }
            
        } else {
            requiredMargin = (markToMarketPnl * receiverVariationMarginBips) / BIPS_DIVISOR;
            variationMargin = BIPS_DIVISOR - receiverVariationMarginBips;
            if (initialUnderlyingPrice > newUnderlyingPrice) {
                liquidationPnl = ((initialUnderlyingPrice - newUnderlyingPrice) * liquidatedUnits * variationMargin) / DECIMAL_BIPS_DIVISOR;
                _updateMargins(receiver, payer, requiredMargin + liquidationPnl);
            } else {
                liquidationPnl = ((newUnderlyingPrice - initialUnderlyingPrice) * liquidatedUnits * variationMargin) / DECIMAL_BIPS_DIVISOR;
                _updateMargins(receiver, payer, requiredMargin);
                _updateMargins(payer, receiver, liquidationPnl);
            }
            
        }
    }


    /**
     * @notice Update the variation margin bips
     * @param receiverMarginBips The receiver margin bips.
     * @param payerMarginBips The payer margin bips.
     * @param underlyingPrice The new underlying price to trigger the position closing
     * @dev Set the side that has to pay to 10000 bips.
     */
    function closePosition(uint256 receiverMarginBips, uint256 payerMarginBips, uint256 underlyingPrice) external onlyOperator
    {
        //update variation margins
        updateVariationMarginBips(receiverMarginBips, payerMarginBips);
        //update position
        updatePositions(underlyingPrice);
        //set notional value to 0
        updateNotionalValue(underlyingPrice, 0);

        state = CLOSED;

        emit ClosePosition(receiverMarginBips, payerMarginBips, underlyingPrice);
    }

    /**
     * @notice Update the variation margin bips
     * @param receiverMarginBips The receiver margin bips.
     * @param payerMarginBips The payer margin bips
     */
    function updateVariationMarginBips(uint256 receiverMarginBips, uint256 payerMarginBips) public onlyOperator
    {
        
        receiverVariationMarginBips = receiverMarginBips;
        payerVariationMarginBips = payerMarginBips;

        emit UpdateVariationMargins(receiverVariationMarginBips, payerVariationMarginBips);
    }


    /**
     * @notice Update the referencePrice
     * @param newReferencePrice The new reference price.
     */
    function updateReferencePrice(uint256 newReferencePrice) public onlyOperator
    {
        
        referencePrice = newReferencePrice;

        emit UpdateReferencePrice(referencePrice);
    }

    /**
     * @notice Update the notional value of the swap via the initial underlying price and swap contract units
     * @param newInitialUnderlyingPrice The new initial underlying price.
     * @param newSwapContractUnits The new swap contract units amount.
     */
    function updateNotionalValue(uint256 newInitialUnderlyingPrice, uint256 newSwapContractUnits) public onlyOperator
    {
        swapContractData.initialUnderlyingPrice = newInitialUnderlyingPrice;
        swapContractData.swapContractUnits = newSwapContractUnits;

        emit UpdateNotionalValue(newInitialUnderlyingPrice, newSwapContractUnits);
        //update swap contract manager
        _updateSwapContractManagerData(newInitialUnderlyingPrice, newSwapContractUnits);

        if (state == CLOSED) {
            state = ACTIVE;
        }
    }

    /**
     * @notice Update the margin positions of the receiver and payer.
     * @param underlyingPrice The underlying price use to calculate PnL.
     */
    function updatePositions(uint256 underlyingPrice) public onlyOperator
    {
        require(underlyingPrice > 0, '0 Amount');
        //set new price
        newUnderlyingPrice = underlyingPrice;
        //emit
        emit UpdateUnderlyingPrice(newUnderlyingPrice);
        //check for equality
        if (newUnderlyingPrice == referencePrice) {
            return;
        }
        //compare new underlying price
        if (newUnderlyingPrice > referencePrice) {
            _updatePositionGreater();
        } else {
            _updatePositionLesser();
        }
        //set referencePrice as newUnderlyingPrice after positions updated
        referencePrice = newUnderlyingPrice;
    }

    /**
     * @notice Update the margin positions of the receiver and payer if new underlying price greater than initial.
     */
    function _updatePositionGreater() private 
    {
        //set pnlhow
        uint256 markToMarketPnl = ((newUnderlyingPrice - referencePrice) * swapContractData.swapContractUnits) / DECIMAL_DIVISOR;
        uint256 requiredMargin;
        //0 for short direction
        if (swapContractData.direction == 0) {
            requiredMargin = (markToMarketPnl * receiverVariationMarginBips) / BIPS_DIVISOR;
            _updateMargins(swapContractData.receiverSubAccount, swapContractData.payerSubAccount, requiredMargin);
        } else {
            requiredMargin = (markToMarketPnl * payerVariationMarginBips) / BIPS_DIVISOR;
            _updateMargins(swapContractData.payerSubAccount, swapContractData.receiverSubAccount, requiredMargin);
        }
    }

    /**
     * @notice Update the margin positions of the receiver and payer if new underlying price less than initial.
     */
    function _updatePositionLesser() private
    {
        //set pnl
        uint256 markToMarketPnl = ((referencePrice - newUnderlyingPrice) * swapContractData.swapContractUnits) / DECIMAL_DIVISOR;
        uint256 requiredMargin;
        //0 for short direction
        if (swapContractData.direction == 0) {
            requiredMargin = (markToMarketPnl * payerVariationMarginBips) / BIPS_DIVISOR;
            _updateMargins(swapContractData.payerSubAccount, swapContractData.receiverSubAccount, requiredMargin);
        } else {
            requiredMargin = (markToMarketPnl * receiverVariationMarginBips) / BIPS_DIVISOR;
            _updateMargins(swapContractData.receiverSubAccount, swapContractData.payerSubAccount, requiredMargin);
        }
    }

    /**
     * @notice Update the margin positions of the receiver and payer and transfer the correct amounts.
     * @param fromSubAccount The sub account sending the payment.
     * @param toSubAccount The sub account receiving the payment.
     * @param marginAmount The margin amount being transferred.
     */
    function _updateMargins(address fromSubAccount, address toSubAccount, uint256 marginAmount) private
    {
        //call transfer margins
        _transferMargin(fromSubAccount, toSubAccount, marginAmount);
    }

    /**
     * @notice Transfer the margin amount between the correct sub accounts.
     * @param fromSubAccount The sub account sending the payment.
     * @param toSubAccount The sub account receiving the payment.
     * @param marginAmount The margin amount being transferred.
     */
    function _transferMargin(address fromSubAccount, address toSubAccount, uint256 marginAmount) private
    {
        ISubAccount(fromSubAccount).transferMargin(swapContractData.collateralToken, toSubAccount, marginAmount);

        emit TransferMargin(fromSubAccount, toSubAccount, swapContractData.collateralToken, marginAmount);
    }

    /**
     * @notice Return the swapContractData struct.
     */
    function getSwapContractData() external view returns (SwapContractData memory)
    {
        return swapContractData;
    } 

    /**
     * @notice Return the swapContractNotional amount.
     */
    function getSwapContractNotional() external view returns (uint256)
    {
        return (swapContractData.swapContractUnits * swapContractData.initialUnderlyingPrice) / DECIMAL_DIVISOR;
    }

    /**
     * @notice Update the data for this swap in the swap contract manager.
     * @param newInitialUnderlyingPrice the new initial underlying price.
     * @param newSwapContractUnits the new swap contract units.
     */
    function _updateSwapContractManagerData(uint256 newInitialUnderlyingPrice, uint256 newSwapContractUnits) internal 
    {
        //update data in swap contract manager.
        ISwapContractManager(swapContractManager).updateSwapContractNotionalValue(swapIndex, newInitialUnderlyingPrice, newSwapContractUnits);
    }
}
