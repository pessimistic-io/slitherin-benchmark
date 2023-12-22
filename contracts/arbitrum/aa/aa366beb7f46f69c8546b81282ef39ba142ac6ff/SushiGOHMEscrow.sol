//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
 
contract Ownable {
    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     */
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IEscrow {
    function convertToEth() external;
    function updateRecipient(address newRecipient) external;
}


interface IRouter {
    function addLiquidity(address tokenA, address tokenB, uint amountADesired, uint amountBDesired, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityAVAX(address token, uint amountTokenDesired, uint amountTokenMin, uint amountAVAXMin, address to, uint deadline) external payable returns (uint amountToken, uint amountAVAX, uint liquidity);
    function removeLiquidity(address tokenA, address tokenB, uint liquidity, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB);
    function removeLiquidityAVAX(address token, uint liquidity, uint amountTokenMin, uint amountAVAXMin, address to, uint deadline) external returns (uint amountToken, uint amountAVAX);
    function removeLiquidityWithPermit(address tokenA, address tokenB, uint liquidity, uint amountAMin, uint amountBMin, address to, uint deadline, bool approveMax, uint8 v, bytes32 r, bytes32 s) external returns (uint amountA, uint amountB);
    function removeLiquidityAVAXWithPermit(address token, uint liquidity, uint amountTokenMin, uint amountAVAXMin, address to, uint deadline, bool approveMax, uint8 v, bytes32 r, bytes32 s) external returns (uint amountToken, uint amountAVAX);
    function removeLiquidityAVAXSupportingFeeOnTransferTokens(address token, uint liquidity, uint amountTokenMin, uint amountAVAXMin, address to, uint deadline) external returns (uint amountAVAX);
    function removeLiquidityAVAXWithPermitSupportingFeeOnTransferTokens(address token, uint liquidity, uint amountTokenMin, uint amountAVAXMin, address to, uint deadline, bool approveMax, uint8 v, bytes32 r, bytes32 s) external returns (uint amountAVAX);
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapExactAVAXForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts);
    function swapTokensForExactAVAX(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapExactTokensForAVAX(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapAVAXForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline ) external;
    function swapExactAVAXForTokensSupportingFeeOnTransferTokens( uint amountOutMin, address[] calldata path, address to, uint deadline) external payable;
    function swapExactTokensForAVAXSupportingFeeOnTransferTokens( uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external;
    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] memory path) external view returns (uint[] memory amounts);
}



contract SushiGOHMEscrow is Ownable, IEscrow {
    address public recipient;
    IERC20 sushiToken;
    IERC20 spellToken;
    IERC20 wETH;
    IRouter sushiRouter;
    uint256 public MIN_TOKENS_TO_SWAP = 10;
    
    
    constructor() {
        recipient =  0x14897d1510F60640f7C2E5a3eEA48f21EDDD40dB;
        sushiToken = IERC20( 0xd4d42F0b6DEF4CE0383636770eF773390d85c61A);
        spellToken = IERC20( 0x8D9bA570D6cb60C7e3e0F31343Efe75AB8E65FB1);//gOHM
        wETH = IERC20( 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        sushiRouter = IRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
        setAllowances();
    }
    
     function setAllowances() public onlyOwner {
        sushiToken.approve(address(sushiRouter), sushiToken.totalSupply());
        spellToken.approve(address(sushiRouter), spellToken.totalSupply());
        wETH.approve(address(sushiRouter), wETH.totalSupply());
      }
    
    /**
   * @notice Update minimum threshold for external callers
   * @param newValue min threshold in wei
   */
  function updateMinTokensToReinvest(uint newValue) external onlyOwner {
    MIN_TOKENS_TO_SWAP = newValue;
  }
    
    function convertToEth() external override {
        uint256 pending = sushiToken.balanceOf(address(this));
        require(pending >= MIN_TOKENS_TO_SWAP, "MIN_TOKENS_TO_SWAP not met");
         // swap sushi to wETH
        address[] memory path0 = new address[](2);
        path0[0] = address(sushiToken);
        path0[1] = address(wETH);
        uint[] memory amountsOutToken0 = sushiRouter.getAmountsOut(pending, path0);
        uint amountOutToken0 = amountsOutToken0[amountsOutToken0.length - 1];
        sushiRouter.swapExactTokensForTokens(pending, amountOutToken0, path0, address(this), block.timestamp);

        // swap spell to wETH
        uint256 pendingSpell = spellToken.balanceOf(address(this));
        address[] memory path1 = new address[](2);
        path1[0] = address(spellToken);
        path1[1] = address(wETH);
        uint[] memory amountsOutToken1 = sushiRouter.getAmountsOut(pendingSpell, path1);
        uint amountOutToken1 = amountsOutToken1[amountsOutToken1.length - 1];
        sushiRouter.swapExactTokensForTokens(pendingSpell, amountOutToken1, path1, address(this), block.timestamp);

        
       //send to recipient
       wETH.transfer(recipient, wETH.balanceOf(address(this)));
    }
    
    function updateRecipient(address newRecipient) external override onlyOwner {
        recipient = newRecipient;
    }
    
    function revertStrategyOwnership(address strategy) external onlyOwner {
        Ownable instance = Ownable(strategy);
        instance.transferOwnership(owner);
    }
    
   
    
    /**
   * @notice Recover ETH from contract (there should never be any left over in this contract)
   * @param amount amount
   */
  function recoverETH(uint amount) external onlyOwner {
    require(amount > 0, "amount too low");
    payable(owner).transfer(amount);
  }
  
   /**
   * @notice Recover ERC20 from contract (there should never be any left over in this contract)
   * @param tokenAddress address of erc20 to recover (can not = sushiToken || spellToken)
   */
  function recoverERC20(address tokenAddress) external onlyOwner {
    require(tokenAddress != address(sushiToken), "cant recover sushi token");
    require(tokenAddress != address(spellToken), "cant recover spell token");
    require(tokenAddress != address(wETH), "cant recover weth token");
    IERC20 instance = IERC20(tokenAddress);
    instance.transfer(owner, instance.balanceOf(address(this)));
  }
}