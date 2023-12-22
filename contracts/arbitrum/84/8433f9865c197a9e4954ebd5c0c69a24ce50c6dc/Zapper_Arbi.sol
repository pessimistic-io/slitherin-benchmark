//SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "./ISwapRouter.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Returns the number of decimal places
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

/// @title Interface for WETH9
interface IWETH9 is IERC20 {
    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;

    /// @notice Withdraw wrapped ether to get ether
    function withdraw(uint256) external;
}

interface ISwapRouterV3 is ISwapRouter {
    function WETH9() external view returns (address);
}

interface IUPPLUS {
    function mintWithBacking(uint256 numTokens, address recipient)
        external
        returns (uint256);
}

contract Zapper_Arbi {
    // constants
    IERC20 public constant USDC =
        IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    ISwapRouterV3 public constant router =
        ISwapRouterV3(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // UPPLUS Token
    address public UPPLUS; //0xF6BC18ad974E446CE03cfD41D87fFDF44AABB1FC

    address public admin;
    
    constructor() {
        UPPLUS = 0xF6BC18ad974E446CE03cfD41D87fFDF44AABB1FC;
        admin = msg.sender;
    }

    receive() external payable {
        zapWithETH(0);
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Caller is not admin!");
        _;
    }

    function zapWithETH(uint256 minOut) public payable {
        IWETH9(router.WETH9()).deposit{value: msg.value}();
        // convert token to Underlying
        _convert(msg.value);

        // require minOut
        uint256 bal = USDC.balanceOf(address(this));
        require(bal >= minOut, "Min Out");

        // USDC.approve(UPPLUS, bal);

        // IUPPLUS(UPPLUS).mintWithBacking(bal, msg.sender);

        _refundDust(msg.sender);
    }

    function _convert(uint256 amountIn) internal {
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: router.WETH9(),
                tokenOut: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8,
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp + 10,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap.
        router.exactInputSingle(params);
    }

    function _refundDust(address recipient) internal {
        uint256 bal0 = USDC.balanceOf(address(this));
        if (bal0 > 0) {
            USDC.transfer(recipient, bal0);
        }
    }

    function changeUPPLUS(address _new) external onlyAdmin {
        UPPLUS = _new;
    }

    function changeAdmin(address _new) external onlyAdmin {
        admin = _new;
    }
}

