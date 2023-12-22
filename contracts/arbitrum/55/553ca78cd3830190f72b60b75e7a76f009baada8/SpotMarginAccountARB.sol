// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import { SubAccount } from "./SubAccount.sol";
import { IERC20 } from "./IERC20.sol";

contract SpotMarginAccountARB is SubAccount {

    /*///////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Disable initializers.
     */
    constructor () {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract. Only called once.
     * @param ownerAddr owner.
     * @param operatorAddr operator.
     * @param feeCollectorAddr fee collector.
     * @param swapContractManagerAddr swap contract manager.
     * @param counterPartyRegistryAddr counter party registry.
     */
    function initialize (
        address ownerAddr,
        address operatorAddr,
        address feeCollectorAddr,
        address swapContractManagerAddr,
        address counterPartyRegistryAddr) external initializer {
        _initSubAccount(
            ownerAddr,
            operatorAddr,
            feeCollectorAddr,
            swapContractManagerAddr,
            counterPartyRegistryAddr
        );
    }

    /*///////////////////////////////////////////////////////////////
                        Modifiers
    //////////////////////////////////////////////////////////////*/


    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwnerOrOperator() {
        require(msg.sender == owner || msg.sender == operator, "not owner or operator");
        _;
    }

    /*///////////////////////////////////////////////////////////////
                            Base Operations
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the active loan contract address
     * @param loan The address of the loan to add.
     */
    function addLoanContract(address loan) external onlyOperator onlyIfInitialized
    {
        _addLoanContract(loan);
    }

    /**
     * @notice Remove a loan contract address
     * @param loan The address of the loan to add.
     */
    function removeLoanContract(address loan) external onlyOperator onlyIfInitialized
    {
        _removeLoanContract(loan);
    }

    /**
     * @notice Set the active strategy contract address
     * @param strategyContractAddress The address of the strategy contract.
     */
    function setActiveStrategy(address strategyContractAddress) external onlyOwnerOrOperator onlyIfInitialized
    {
        _setActiveStrategy(strategyContractAddress);
    }

    /**
     * @notice Close the subaccount.
     * @dev The subaccount cannot be reopened after calling this function.
     */
    function closeSubAccount() external onlyOperator onlyIfInitialized
    {
        _closeSubAccount();
    }

    /**
     * @notice Deploys a twap contract for the subaccount
     * @param traderAddr The address that executes orders through the twap contract.
     * @param depositorAddr The address that deposits into the twap contract.
     * @param sellingToken The token sold through the twap contract.
     * @param buyingToken The token bought through the twap contract.
     */
    function deployTwap(
        address traderAddr, 
        address depositorAddr, 
        IERC20 sellingToken, 
        IERC20 buyingToken) external onlyOperator onlyIfInitialized
    {
        _deployTwap(traderAddr, depositorAddr, sellingToken, buyingToken);
    }

    /**
     * @notice Update Price Limit for a twap order
     * @param priceLimit Price limit for twap order
     */
    function twapUpdatePriceLimit(uint256 priceLimit) external onlyOperator onlyIfInitialized
    {
        _twapUpdatePriceLimit(priceLimit);
    }

    /**
     * @notice Open a twap order
     * @param durationInMins The duration of the twap
     * @param targetQty The target quantity for the twap
     * @param chunkSize The chunk size for the twap
     * @param maxPriceLimit The max price limit for the twap
     */
    function twapOpenOrder(
        uint256 durationInMins, 
        uint256 targetQty, 
        uint256 chunkSize, 
        uint256 maxPriceLimit) external onlyOperator onlyIfInitialized 
    {
        _twapOpenOrder(durationInMins, targetQty, chunkSize, maxPriceLimit);
    }

    /**
     * @notice Deposit into twap contract
     * @param amount Amount of sell token to deposit into twap contract
     */
    function twapDeposit(IERC20 token, uint256 amount) external onlyOperator onlyIfInitialized
    {
        _twapDeposit(token, amount);
    }

    /**
     * @notice Cancel active twap order
     */
    function twapCancelOrder() external onlyOperator onlyIfInitialized
    {
        _twapCancelOrder();
    }

    /**
     * @notice Close active twap order
     * @dev This will transfer all tokens in twap contract back to subaccount. 
     */
    function twapCloseOrder() external onlyOperator onlyIfInitialized
    {
        _twapCloseOrder();
    }
    /**
     * @notice Deploy to the active strategy
     * @param token token to deposit.
     * @param amount amount of tokens to deposit.
     * @param minAmount minimum amount of tokens to receive.
     */
    function deployToStrategy(IERC20 token, uint256 amount, uint256 minAmount) external onlyOwnerOrOperator onlyIfInitialized
    {
        _deployToStrategy(token, amount, minAmount);
    }

    /**
     * @notice Withdraw from the active strategy
     * @param token token to withdraw.
     * @param amount amount of tokens to burn.
     * @param minAmount minimum amount of tokens to receive.
     */
    function withdrawFromStrategy(IERC20 token, uint256 amount, uint256 minAmount) external onlyOwnerOrOperator onlyIfInitialized
    {
        _withdrawFromStrategy(token, amount, minAmount);
    }

    /**
     * @notice Deposit only to active strategy
     * @param token token to deposit.
     * @param amount amount of tokens to deposit.
     */
    function depositToStrategy(IERC20 token, uint256 amount) external onlyOwnerOrOperator onlyIfInitialized
    {
        _depositToStrategy(token, amount);
    }

    /**
     * @notice Withdraw only from active strategy
     * @param token token to deposit.
     * @param amount amount of tokens to deposit.
     */
    function withdrawOnlyFromStrategy(IERC20 token, uint256 amount) external onlyOwnerOrOperator onlyIfInitialized
    {
        _withdrawOnlyFromStrategy(token, amount);
    }

    /**
     * @notice Deposit into the sub account. 
     * @param token token to deposit.
     * @param amount amount of tokens to deposit.
     */
    function deposit(IERC20 token, uint256 amount) external onlyOwner onlyIfInitialized
    { 
        _deposit(token, amount);
    }

    /**
     * @notice Withdraw from the sub account. 
     * @param token token to withdraw.
     * @param amount amount of tokens to withdraw.
     */
    function withdraw(IERC20 token, uint256 amount) external onlyOwner onlyIfInitialized
    {
        _withdraw(token, amount);
    }

    /**
     * @notice Withdraw from the sub account to the owner address. 
     * @param token token to withdraw.
     * @param amount amount of tokens to withdraw.
     */
    function withdrawToOwner(IERC20 token, uint256 amount) external onlyOperator onlyIfInitialized
    {
        _withdrawToOwner(token, amount);
    }

    /**
     * @notice Partially unwind a position. 
     * @param loan The address of the loan
     * @param token The token to swap
     * @param amount The amount to swap.
     * @param targetAmount The target amount to use when repaying debt.
     * @param swapCallData The callData to pass to the paraswap router. Generated offchain.
     */
    function partialUnwind(address loan, IERC20 token, uint256 amount, uint256 targetAmount, bytes memory swapCallData) external onlyOperator onlyIfInitialized
    {
        _partialUnwind(loan, token, amount, targetAmount, swapCallData);
    }

    /**
     * @notice Fully unwind a position. 
     * @param loan The address of the loan
     * @param token The token to swap
     * @param amount The amount to swap.
     * @param swapCallData The callData to pass to the paraswap router. Generated offchain.
     */
    function fullUnwind(address loan, IERC20 token, uint256 amount, bytes memory swapCallData) external onlyOperator onlyIfInitialized
    {
        _fullUnwind(loan, token, amount, swapCallData);
    }

    /**
     * @notice Swap rewards via the paraswap router.
     * @param token The token to swap.
     * @param amount The amount of tokens to swap. 
     * @param callData The callData to pass to the paraswap router. Generated offchain.
     */
    function swap(IERC20 token, uint256 amount, bytes memory callData) external payable onlyOperator onlyIfInitialized
    {
        //call internal swap
        _swap(token, amount, callData);
    }

    /**
     * @notice Accept the loan contract.
     * @param loan The address of the loan.
     */
    function acceptLoan(address loan) external onlyOperator onlyIfInitialized
    {
        _acceptLoan(loan);
    }

    /**
     * @notice Withdraw principal amount from the loan contract.
     * @param loan The address of the loan.
     */
    function withdrawLoanPrincipal(address loan) external onlyOperator onlyIfInitialized
    {
        _withdrawLoanPrincipal(loan);
    }

    /**
     * @notice Repay the principal amount for the loan.
     * @param loan The address of the loan.
     * @param amount Amount of principal to pay back.
     */
    function repayLoanPrincipal(address loan, uint256 amount) external onlyOperator onlyIfInitialized
    {
        _repayLoanPrincipal(loan, amount);
    }

    /**
     * @notice Repay accrued interest on the loan.
     * @param loan The address of the loan.
     */
    function repayLoanInterest(address loan) external onlyOperator onlyIfInitialized
    {
        _repayLoanInterest(loan);
    }

    /**
     * @notice Set subAccountState to Margin Call as a warning level.
     */
    function marginCall() external onlyOperator onlyIfInitialized
    {
        _marginCall();
    }

    /**
     * @notice Transfer a specified amount of margin between sub accounts.
     * @param token The token to transfer between accounts.
     * @param toSubAccount The account to transfer tokens to.
     * @param marginAmount The amount of margin to transfer between accounts.
     */
    function transferMargin(IERC20 token, address toSubAccount, uint256 marginAmount) external onlySwapContract onlyIfInitialized 
    {
        _transferMargin(token, toSubAccount, marginAmount);
    }

    /**
     * @notice Transfer a specified amount of tokens to the fractal fee collector.
     * @param token The token to transfer to the fee collector.
     * @param amount The amount to transfer to the fractal fee collector.
     */
    function transferOriginationFee(IERC20 token, uint256 amount) external onlySwapContractManager onlyIfInitialized
    {
        _transferOriginationFee(token, amount);
    }
}
