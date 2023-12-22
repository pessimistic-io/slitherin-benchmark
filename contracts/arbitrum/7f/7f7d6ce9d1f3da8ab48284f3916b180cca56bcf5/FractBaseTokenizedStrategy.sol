// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import { Ownable } from "./Ownable.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IParaSwapAugustus } from "./IParaSwapAugustus.sol";
import { ERC20 } from "./ERC20.sol";

/**
 * @notice FractBaseStrategy should be inherited by new strategies.
 */
abstract contract FractBaseTokenizedStrategy is Ownable, ERC20 {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                        Constants and Immutables
    //////////////////////////////////////////////////////////////*/

    //paraswap swapper contract
    address constant PARASWAP = 0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57;
    
    // Constant used as a bips divisor. 
    uint256 constant BIPS_DIVISOR = uint256(10000);

    // Constant for scaling values.
    uint256 constant ONE_ETHER = uint256(10**18);

    /*///////////////////////////////////////////////////////////////
                        Constructor
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Initializes the contract setting the deployer as the operator.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals)
    {
        _operator = msg.sender;
    }

    /*///////////////////////////////////////////////////////////////
                        State Variables
    //////////////////////////////////////////////////////////////*/

    //operator address used to call specific functions offchain.
    address internal _operator;

    /*///////////////////////////////////////////////////////////////
                        Events
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice This event is fired when the strategy receives a deposit.
     * @param account Specifies the depositor address.
     * @param amount Specifies the deposit amount.
     */
    event Deposit(address indexed account, uint amount);

    /**
     * @notice This event is fired when the strategy receives a withdrawal.
     * @param account Specifies the withdrawer address.
     * @param amount Specifies the withdrawal amount,
     */
    event Withdraw(address indexed account, uint amount);

    /**
     * @notice This event is fired when the strategy receives a withdrawal to owner.
     * @param token Specifies the token address.
     * @param amount Specifies the withdrawal amount,
     */
    event WithdrawToOwner(IERC20 token, uint amount);

    /*///////////////////////////////////////////////////////////////
                        Modifiers
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Only called by operator
     */
    modifier onlyOperator() {
        require(msg.sender == _operator, "Only Operator");
        _;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwnerOrOperator() {
        require(msg.sender == owner || msg.sender == _operator, "not owner or operator");
        _;
    }

    /*///////////////////////////////////////////////////////////////
                        Setters
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the vault address the strategy will receive deposits from. 
     * @param operatorAddress Specifies the address of the poolContract. 
     */
    function setOperator(address operatorAddress) external onlyOwner {
        _operator = operatorAddress;
    }

    /*///////////////////////////////////////////////////////////////
                            ERC20 Operations
    //////////////////////////////////////////////////////////////*/

    function transfer(address to, uint256 amount) public override onlyOwner returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override onlyOwner returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }


    /*///////////////////////////////////////////////////////////////
                            Base Operations
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit into the strategy
     * @param token token to deposit.
     * @param amount amount of tokens to deposit.
     */
    function _deposit(IERC20 token, uint256 amount) internal 
    {
        emit Deposit(msg.sender, amount);

        token.safeTransferFrom(msg.sender, address(this), amount);

        _mint(msg.sender, amount);
    }

    /**
     * @notice Withdraw from the strategy 
     * @param token token to withdraw.
     * @param amount amount of tokens to withdraw.
     */
    function _withdraw(IERC20 token, uint256 amount) internal 
    {
        emit Withdraw(msg.sender, amount);

        token.safeTransfer(msg.sender, amount);

        _burn(msg.sender, amount);
    }

    /**
     * @notice Withdraw from the strategy to the owner.
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
     * @notice Withdraw eth locked in contract back to owner
     * @param amount amount of eth to send.
     */
    function withdrawETH(uint256 amount) external onlyOperator 
    {
        (bool success,) = payable(owner).call{value: amount}("");
        require(success, "withdraw failed");
    }

    /**
     * @notice Helper function to burn excess receipt tokens.
     * @param amount amount of tokens to burn.
     */
    function burnTokens(uint256 amount) external onlyOperator
    {
        _burn(owner, amount);
    }       
}
