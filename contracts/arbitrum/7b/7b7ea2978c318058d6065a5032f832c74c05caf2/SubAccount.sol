// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import { IFractBaseStrategy } from "./IFractBaseStrategy.sol";
import { IOpenTermLoan } from "./IOpenTermLoan.sol";
import { ICounterPartyRegistry } from "./ICounterPartyRegistry.sol";
import { IParaSwapAugustus } from "./IParaSwapAugustus.sol";
import { ITwapOrder } from "./ITwapOrder.sol";
import { TwapOrder } from "./TwapOrder.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { Initializable } from "./Initializable.sol";

abstract contract SubAccount is Initializable {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                        Constants and Immutables
    //////////////////////////////////////////////////////////////*/
    
    address constant internal PARASWAP = 0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57;

    uint8 constant ACTIVE = 0;
    uint8 constant USER_FUNDED = 1;
    uint8 constant MARGIN_FUNDED = 2;
    uint8 constant MARGIN_CALL = 3;
    uint8 constant LIQUIDATED = 4;
    uint8 constant DEFAULTED = 5;
    uint8 constant CLOSED = 6;


    /*///////////////////////////////////////////////////////////////
                        State Variables
    //////////////////////////////////////////////////////////////*/

    uint8 public subAccountState;
    address public owner;
    address public operator;
    address public feeCollector;
    address public swapContractManager;
    address public counterPartyRegistry;
    address public activeStrategy;
    address public twap;

    address[] public loanAddresses;

    /*///////////////////////////////////////////////////////////////
                        Events
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the contract receives Native Asset.
     * @param sender The addresse that sends Native Asset.
     * @param amount The amount of Native Asset sent.
     */
    event Received(address sender, uint256 amount);

    /**
     * @notice This event is fired when the subaccount receives a deposit.
     * @param account Specifies the depositor address.
     * @param amount Specifies the deposit amount.
     */
    event Deposit(address account, uint amount);

    /**
     * @notice This event is fired when the subaccount receives a withdrawal.
     * @param account Specifies the withdrawer address.
     * @param amount Specifies the withdrawal amount,
     */
    event Withdraw(address account, uint amount);

    /**
     * @notice This event is fired when the subaccount receives a withdrawal to owner.
     * @param token Specifies the token address.
     * @param amount Specifies the withdrawal amount,
     */
    event WithdrawToOwner(IERC20 token, uint amount);

    /**
     * @notice This event is fired when the subaccount adds a loan contract.
     * @param loan Address of the loan contract.
     */
    event AddLoan(address loan);

    /**
     * @notice This event is fired when the subaccount removes a loan contract.
     * @param loan Address of the loan contract.
     */
    event RemoveLoan(address loan);

    /**
     * @notice This event is fired when the subaccount is partially liquidated.
     * @param liquidator Address of liquidator.
     * @param state The state of the subaccount after liquidation.
     */
    event PartialLiquidation(address liquidator, uint8 state);

    /**
     * @notice This event is fired when the subaccount is fully liquidated.
     * @param liquidator Address of liquidator.
     * @param state The state of the subaccount after liquidation.
     */
    event FullLiquidation(address liquidator, uint8 state);

    /*///////////////////////////////////////////////////////////////
                        Modifiers
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Safety check for all possible versions of this contract.
     */
    modifier onlyIfInitialized {
        require(_getInitializedVersion() != type(uint8).max, "Contract was not initialized yet");
        _;
    }

    /**
     * @notice Only called by owner
     */
    modifier onlyOwner() {
        require(owner == msg.sender, "not owner");
        _;
    }

    /**
     * @notice Only called by controller
     */
    modifier onlyOperator() {
        require(msg.sender == operator, "Only Operator");
        _;
    }

    /**
     * @notice Only called by active swap contract
     */
    modifier onlySwapContract() {
        require(ICounterPartyRegistry(counterPartyRegistry).getSwapContract(msg.sender), 'Only Swap Contract');
        _;
    }

    /**
     * @notice Only called by swap contract manager
     */
    modifier onlySwapContractManager() {
        require(msg.sender == swapContractManager, 'Only Swap Contract Manager');
        _;
    }

    /*///////////////////////////////////////////////////////////////
                        Receive
    //////////////////////////////////////////////////////////////*/

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /*///////////////////////////////////////////////////////////////
                            Base Operations
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the contract. Only called once.
     * @param ownerAddr owner.
     * @param operatorAddr operator.
     * @param feeCollectorAddr fee collector.
     * @param swapContractManagerAddr swap contract mananger.
     * @param counterPartyRegistryAddr counter party registry.
     */
    function _initSubAccount(
        address ownerAddr,
        address operatorAddr,
        address feeCollectorAddr,
        address swapContractManagerAddr,
        address counterPartyRegistryAddr) internal onlyInitializing 
    {
        owner = ownerAddr;
        operator = operatorAddr;
        feeCollector = feeCollectorAddr;
        swapContractManager = swapContractManagerAddr;
        counterPartyRegistry = counterPartyRegistryAddr;
    }

    /**
     * @notice Set the active loan contract address
     * @param loan The address of the loan to add.
     */
    function _addLoanContract(address loan) internal 
    {
        loanAddresses.push(loan);

        emit AddLoan(loan);
    }

    /**
     * @notice Remove a loan contract address
     * @param loan The address of the loan to remove.
     */
    function _removeLoanContract(address loan) internal 
    {
        //store new array
        address[] storage loanToRemove = loanAddresses;
        //cache length
        uint256 length = loanToRemove.length;
        for (uint256 i = 0; i < length;) {
            if (loan == loanToRemove[i]) {
                loanToRemove[i] = loanToRemove[length - 1];
                loanToRemove.pop();
                break;
            }

            unchecked { ++i; }
        }
        loanAddresses = loanToRemove;

        emit RemoveLoan(loan);
    }

    /**
     * @notice Set the active strategy contract address
     * @param strategyContractAddress The address of the strategy contract.
     */
    function _setActiveStrategy(address strategyContractAddress) internal 
    {
        activeStrategy = strategyContractAddress;
    }

    /**
     * @notice Close the subaccount.
     * @dev The subaccount cannot be reopened after calling this function.
     */
    function _closeSubAccount() internal
    {
        subAccountState = CLOSED; 
    }

    /**
     * @notice Deploys a twap contract for the subaccount
     * @param traderAddr The address that executes orders through the twap contract.
     * @param depositorAddr The address that deposits into the twap contract.
     * @param sellingToken The token sold through the twap contract.
     * @param buyingToken The token bought through the twap contract.
     */
    function _deployTwap(address traderAddr, address depositorAddr, IERC20 sellingToken, IERC20 buyingToken) internal 
    {
        TwapOrder instance = new TwapOrder();
        instance.initialize(traderAddr, depositorAddr, sellingToken, buyingToken);
        instance.transferOwnership(address(this));
        twap = address(instance);
    }

    /**
     * @notice Update Price Limit for a twap order
     * @param priceLimit Price limit for twap order
     */
    function _twapUpdatePriceLimit(uint256 priceLimit) internal
    {
        ITwapOrder(twap).updatePriceLimit(priceLimit); 
    }

    /**
     * @notice Open a twap order
     * @param durationInMins The duration of the twap
     * @param targetQty The target quantity for the twap
     * @param chunkSize The chunk size for the twap
     * @param maxPriceLimit The max price limit for the twap
     */
    function _twapOpenOrder(uint256 durationInMins, uint256 targetQty, uint256 chunkSize, uint256 maxPriceLimit) internal 
    {
        ITwapOrder(twap).openOrder(durationInMins, targetQty, chunkSize, maxPriceLimit);
    }

    /**
     * @notice Deposit into twap contract
     * @param amount Amount of sell token to deposit into twap contract
     */
    function _twapDeposit(IERC20 token, uint256 amount) internal 
    {
        token.safeApprove(twap, amount);
        ITwapOrder(twap).deposit(amount);
        token.safeApprove(twap, 0);
    }

    /**
     * @notice Cancel active twap order
     */
    function _twapCancelOrder() internal 
    {
        ITwapOrder(twap).cancelOrder();
    }

    /**
     * @notice Close active twap order
     * @dev This will transfer all tokens in twap contract back to subaccount. 
     */
    function _twapCloseOrder() internal
    {
        ITwapOrder(twap).closeOrder();
    }

    /**
     * @notice Deploy to the active strategy
     * @param token token to deposit.
     * @param amount amount of tokens to deposit.
     * @param minAmount minimum amount of tokens to receive.
     */
    function _deployToStrategy(IERC20 token, uint256 amount, uint256 minAmount) internal
    
    {
        //check state
        require(subAccountState == USER_FUNDED || subAccountState == MARGIN_FUNDED, 'not funded');
        //approve strategy as spender
        token.safeApprove(activeStrategy, amount);
        //transfer the amount to strategy
        IFractBaseStrategy(activeStrategy).deposit(token, amount);
        //enter position
        IFractBaseStrategy(activeStrategy).enterPosition(token, amount, minAmount);
        //set approval back to 0
        token.safeApprove(activeStrategy, 0);
    }

    /**
     * @notice Withdraw from the active strategy
     * @param token token to withdraw.
     * @param amount amount of tokens to withdraw.
     * @param minAmount minimum amount of tokens to receive.
     */
    function _withdrawFromStrategy(IERC20 token, uint256 amount, uint256 minAmount) internal
    {
        //check state
        require(subAccountState == USER_FUNDED || subAccountState == MARGIN_FUNDED, 'not funded');
        //exit position
        IFractBaseStrategy(activeStrategy).exitPosition(token, amount, minAmount);
        //call withdraw on active strategy
        IFractBaseStrategy(activeStrategy).withdraw(token, token.balanceOf(activeStrategy));
    }


    /**
     * @notice Deposit only to active strategy
     * @param token token to deposit.
     * @param amount amount of tokens to deposit.
     */
    function _depositToStrategy(IERC20 token, uint256 amount) internal
    
    {
        //check state
        require(subAccountState == USER_FUNDED || subAccountState == MARGIN_FUNDED, 'not funded');
        //approve strategy as spender
        token.safeApprove(activeStrategy, amount);
        //transfer the amount to strategy
        IFractBaseStrategy(activeStrategy).deposit(token, amount);
        //revoke approval
        token.safeApprove(activeStrategy, 0);
    }

    /**
     * @notice Withdraw only from active strategy
     * @param token token to deposit.
     * @param amount amount of tokens to deposit.
     */
    function _withdrawOnlyFromStrategy(IERC20 token, uint256 amount) internal
    {
        //check state
        require(subAccountState == USER_FUNDED || subAccountState == MARGIN_FUNDED, 'not funded');
        //call withdraw on active strategy
        IFractBaseStrategy(activeStrategy).withdraw(token, amount);
    }

    /**
     * @notice Deposit into the sub account. 
     * @param token token to deposit.
     * @param amount amount of tokens to deposit.
     */
    function _deposit(IERC20 token, uint256 amount) internal 
    {
        require(subAccountState == ACTIVE || subAccountState == USER_FUNDED || subAccountState == MARGIN_FUNDED || subAccountState == MARGIN_CALL, 'not active or funded');

        emit Deposit(msg.sender, amount);

        subAccountState = USER_FUNDED;

        _checkLoan(); 

        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Withdraw from the sub account. 
     * @param token token to withdraw.
     * @param amount amount of tokens to withdraw.
     */
    function _withdraw(IERC20 token, uint256 amount) internal 
    {
        //check state
        require(subAccountState == USER_FUNDED || subAccountState == MARGIN_FUNDED, 'not funded');

        emit Withdraw(msg.sender, amount);

        token.safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Withdraw from the sub account. 
     * @param token token to withdraw.
     * @param amount amount of tokens to withdraw.
     */
    function _withdrawToOwner(IERC20 token, uint256 amount) internal 
    {

        emit WithdrawToOwner(token, amount);

        token.safeTransfer(owner, amount);
    }

    /**
     * @notice Swap rewards via the paraswap router.
     * @param token The token to swap.
     * @param amount The amount of tokens to swap. 
     * @param callData The callData to pass to the paraswap router. Generated offchain.
     */
    function _swap(IERC20 token, uint256 amount, bytes memory callData) internal 
    {
        //get TokenTransferProxy depending on chain.
        address tokenTransferProxy = IParaSwapAugustus(PARASWAP).getTokenTransferProxy();
        // allow TokenTransferProxy to spend token
        token.safeApprove(tokenTransferProxy, amount);
        //swap
        (bool success,) = PARASWAP.call(callData);
        //check swap
        require(success, "swap failed");
        //set approval back to 0
        token.safeApprove(tokenTransferProxy, 0);
    }


    /**
     * @notice Accept the loan contract.
     * @param loan The address of the loan.
     */
    function _acceptLoan(address loan) internal 
    {
        //check state
        require(subAccountState == USER_FUNDED || subAccountState == MARGIN_FUNDED, 'not funded');
        //get principal token
        address token = IOpenTermLoan(loan).principalToken();
        //approve loan contract as spender for white glove contract.
        IERC20(token).safeApprove(loan, type(uint256).max);
        //commit to loan
        IOpenTermLoan(loan).borrowerCommitment();
    }

    /**
     * @notice Withdraw principal amount from the loan contract.
     * @param loan The address of the loan.
     */
    function _withdrawLoanPrincipal(address loan) internal 
    {

        require(subAccountState == USER_FUNDED || subAccountState == MARGIN_FUNDED, 'not funded');

        subAccountState = MARGIN_FUNDED;

        IOpenTermLoan(loan).withdraw();
    }

    /**
     * @notice Repay the principal amount for the loan.
     * @param loan The address of the loan.
     * @param amount Amount of principal to pay back.
     */
    function _repayLoanPrincipal(address loan, uint256 amount) internal 
    {
        IOpenTermLoan(loan).repayPrincipal(amount);
    }

    /**
     * @notice Repay accrued interest on the loan.
     * @param loan The address of the loan.
     */
    function _repayLoanInterest(address loan) internal 
    {

        IOpenTermLoan(loan).repayInterests();
    }

    /**
     * @notice Set subAccountState to Margin Call as a warning level.
     */
    function _marginCall() internal 
    {
        //check state
        require(subAccountState == MARGIN_FUNDED, 'not funded');
        //set state
        subAccountState = MARGIN_CALL;
    }

    /**
     * @notice Partially unwind a position. 
     * @param loan The address of the loan to pay off.
     * @param token The token to swap
     * @param amount The amount to swap.
     * @param targetAmount The target amount to use when paying off interest and debt.
     * @param swapCallData The callData to pass to the paraswap router. Generated offchain.
     */
    function _partialUnwind(
        address loan,
        IERC20 token, 
        uint256 amount,
        uint256 targetAmount, 
        bytes memory swapCallData) internal 
    {
        //get principalDebt and interestOwed amount
        (,,,uint256 interestOwed,,,,,,) = IOpenTermLoan(loan).getDebt();
        //get principal token
        address principalToken = IOpenTermLoan(loan).principalToken();
        //repay amount
        uint256 repayAmount;
        //principle liquidation fee
        uint256 principleLiquidationFee = (targetAmount * 200) / 10000;
        //transfer
        IERC20(principalToken).safeTransfer(feeCollector, principleLiquidationFee);
        //check if interest owed
        if (interestOwed > 0) {
            //calculate fees
            uint256 interestLiquidationFee = (interestOwed * 200) / 10000;
            //transfer fees
            IERC20(principalToken).safeTransfer(feeCollector, interestLiquidationFee);  
            //repay
            repayAmount = targetAmount - interestOwed - principleLiquidationFee - interestLiquidationFee;
            //if no token passed == no collateral to swap
            if (address(token) == address(0)) {
                //pay interest
                _repayLoanInterest(loan);
                //use remaining balance to partially pay principal debt amount
                _repayLoanPrincipal(loan, repayAmount);
            } else 
            {
                //swap to principalToken
                _swap(token, amount, swapCallData);
                //pay interest
                _repayLoanInterest(loan);
                //use remaining balance to partially pay principal debt amount
                _repayLoanPrincipal(loan, repayAmount);
            }
        } else {
            //repay
            repayAmount = targetAmount - principleLiquidationFee;
            //if no token passed == no collateral to swap
            if (address(token) == address(0)) {
                //use remaining balance to partially pay principal debt amount
                _repayLoanPrincipal(loan, repayAmount);
            } else 
            {
                //swap to principalToken
                _swap(token, amount, swapCallData);
                //use remaining balance to partially pay principal debt amount
                _repayLoanPrincipal(loan, repayAmount);  
            }
        }

        emit PartialLiquidation(msg.sender, subAccountState);
    }

    /**
     * @notice Fully unwind a position. 
     * @param loan The address of the loan.
     * @param token The token to swap
     * @param amount The amount to swap.
     * @param swapCallData The callData to pass to the paraswap router. Generated offchain.
     */
    function _fullUnwind(
        address loan,
        IERC20 token, 
        uint256 amount,
        bytes memory swapCallData) internal
    {
        //get principalDebt and interestOwed amount
        (,,uint256 principalDebtAmount,uint256 interestOwed,,,,,,) = IOpenTermLoan(loan).getDebt();
        //get principal token
        address principalToken = IOpenTermLoan(loan).principalToken();
        //principle liquidation fee
        uint256 principleLiquidationFee = (principalDebtAmount * 200) / 10000;
        //transfer fee
        IERC20(principalToken).safeTransfer(feeCollector, principleLiquidationFee);
        //if interest is owed
        if (interestOwed > 0) {
            //calculate fees
            uint256 interestLiquidationFee = (interestOwed * 200) / 10000;
            //transfer fees
            IERC20(principalToken).safeTransfer(feeCollector, interestLiquidationFee);  
            //if nothing to swap
            if (address(token) == address(0)) {
                //pay interest
                _repayLoanInterest(loan);
                //use remaining balance to partially pay principal debt amount
                if (IERC20(principalToken).balanceOf(address(this)) >= principalDebtAmount) {
                    //repay loan
                    _repayLoanPrincipal(loan, principalDebtAmount);
                    //set state
                    subAccountState = LIQUIDATED;
                } else
                {
                    //repay whatever account can
                    _repayLoanPrincipal(loan, IERC20(principalToken).balanceOf(address(this)));
                    //set state
                    subAccountState = DEFAULTED;
                }
            } else 
            {
                //swap to principalToken
                _swap(token, amount, swapCallData);
                //pay interest
                _repayLoanInterest(loan);
                //use remaining balance to partially pay principal debt amount
                if (IERC20(principalToken).balanceOf(address(this)) >= principalDebtAmount) {
                    //repay loan
                    _repayLoanPrincipal(loan, principalDebtAmount);
                    //set state
                    subAccountState = LIQUIDATED;
                } else
                {
                    //repay whatever account can
                    _repayLoanPrincipal(loan, IERC20(principalToken).balanceOf(address(this)));
                    //set state
                    subAccountState = DEFAULTED;
                }
            }
        } else 
        {
            //if nothing to swap
            if (address(token) == address(0)) {
                //use remaining balance to partially pay principal debt amount
                if (IERC20(principalToken).balanceOf(address(this)) >= principalDebtAmount) {
                    //repay loan
                    _repayLoanPrincipal(loan, principalDebtAmount);
                    //set state
                    subAccountState = LIQUIDATED;
                } else
                {
                    //repay whatever account can
                    _repayLoanPrincipal(loan, IERC20(principalToken).balanceOf(address(this)));
                    //set state
                    subAccountState = DEFAULTED;
                }  
            } else 
            {
                //swap to principalToken
                _swap(token, amount, swapCallData);
                //use remaining balance to partially pay principal debt amount
                if (IERC20(principalToken).balanceOf(address(this)) >= principalDebtAmount) {
                    //repay loan
                    _repayLoanPrincipal(loan, principalDebtAmount);
                    //set state
                    subAccountState = LIQUIDATED;
                } else{
                    //repay whatever account can
                    _repayLoanPrincipal(loan, IERC20(principalToken).balanceOf(address(this)));
                    //set state
                    subAccountState = DEFAULTED;
                }
            }  
        }

        emit FullLiquidation(msg.sender, subAccountState);
    }

    /**
     * @notice Transfer a specified amount of margin between sub accounts.
     * @param token The token to transfer between accounts.
     * @param toSubAccount The account to transfer tokens to.
     * @param marginAmount The amount of margin to transfer between accounts.
     */
    function _transferMargin(IERC20 token, address toSubAccount, uint256 marginAmount) internal 
    {
        require(subAccountState == USER_FUNDED || subAccountState == MARGIN_FUNDED, 'not funded');
        //check that to and from sub accounts are valid.
        require(ICounterPartyRegistry(counterPartyRegistry).getCounterParty(toSubAccount), 'invalid counter party');
        //approve operator as spender of token for maxMarginTransferAmount
        token.safeApprove(toSubAccount, marginAmount);
        //transfer correct amounts based on calculation in the swap contract
        token.safeTransfer(toSubAccount, marginAmount);
        //set approval back to 0
        token.safeApprove(toSubAccount, 0);
    }

    /**
     * @notice Transfer a specified amount of tokens to the fractal fee collector.
     * @param token The token to transfer to the fee collector.
     * @param amount The amount to transfer to the fractal fee collector.
     */
    function _transferOriginationFee(IERC20 token, uint256 amount) internal 
    {
        token.safeApprove(feeCollector, amount);
        //transfer the amount to fee collector
        token.safeTransfer(feeCollector, amount);
        //set approval back to 0
        token.safeApprove(feeCollector, 0);
    }

    function _checkLoan() internal
    {
        if (loanAddresses.length > 0) {
            subAccountState = MARGIN_FUNDED;
        }
    }

    /**
     * @notice Withdraw eth locked in contract back to owner
     * @param amount amount of eth to send.
     */
    function withdrawETH(uint256 amount) external onlyOwner {
        (bool success,) = payable(owner).call{value: amount}("");
        require(success, "withdraw failed");
    }

    function getLoans() external view returns (address[] memory) 
    {
        return loanAddresses;
    }   
}
