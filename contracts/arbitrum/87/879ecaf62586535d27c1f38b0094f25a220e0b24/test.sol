// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./ITEST.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}
 
interface IUniswapV2Router02 {
 
    function factory() external pure returns (address);

 
    // function addLiquidityETH(
    //     address token,
    //     uint256 amountTokenDesired,
    //     uint256 amountTokenMin,
    //     uint256 amountETHMin,
    //     address to,
    //     uint256 deadline
    // )
    //     external
    //     payable
    //     returns (
    //         uint256 amountToken,
    //         uint256 amountETH,
    //         uint256 liquidity
    //     );

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}
 
contract TEST is ITEST, ERC20, Ownable {
    
    uint8 public basetax = 3;
    uint256 public maxSupply;
    uint256 private initialSupply;
    address public sushiswapPair;
    address treasury = 0xBdf67b4168aAa39f6292241f547D52Ab5Cb3cC38;
    IUniswapV2Router02 public sushiswapRouter;
    

    //safeMathuse
    using SafeMath for uint256;
    
    // a mapping from an address to whether or not it can mint / burn

    mapping(address => bool) public isController;

    //Mapping of receivers excluded of the fee

    mapping(address => bool) private excludedFromFee;

    //set defaut trading status to false

    bool public tradingEnabled = false;

    //constructor 

    constructor(uint256 _initialSupply , uint256 _maxSupply) ERC20("TEST", "TEST") 
    {
        IUniswapV2Router02 _sushiswapRouter = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);//
        sushiswapRouter = _sushiswapRouter;
        sushiswapPair = IUniswapV2Factory(_sushiswapRouter.factory())
        .createPair(address(this), 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
        initialSupply = _initialSupply;
        maxSupply = _maxSupply;
        _mint(msg.sender, initialSupply);
    }

    //mints $TEST to a recipient

    function mint(address to_, uint256 amount_)
        external
        onlyController
    {
        _mint(to_, amount_);
    }

    //burns $TEST from a holder

    function burn(address from_, uint256 amount_)
        external
        
        onlyController
    {
        _burn(from_, amount_);
    }

    event ControllerAdded(address newController);

    //enables an address to mint / burn   
    
    function addController(address toAdd_) external onlyOwner {
        isController[toAdd_] = true;
        emit ControllerAdded(toAdd_);
    }

    event ControllerRemoved(address controllerRemoved);

    //disable an address to mint / burn

    function removeController(address toRemove_) external onlyOwner {
        isController[toRemove_] = false;
        emit ControllerRemoved(toRemove_);
    }

    //only controllers

    modifier onlyController() {
        if(isController[_msgSender()] == false) revert("CallerNotController");
        _;
    }

    //trading status function 

     function pause_trading() public onlyController{       
        tradingEnabled = false;
    }

    function enable_trading() public onlyController{
        tradingEnabled = true;
    }
    //Fees functions

    function setExcludedFromFee(address _excluded, bool _excludedValue) external onlyOwner {
        excludedFromFee[_excluded] = _excludedValue;
    
    }
    function isExcluded(address account) public view returns (bool) {
    return excludedFromFee[account];
    }

    //transfer function
    function _transfer(
    address from,
    address to,
    uint256 amount
    
    ) internal override {

    bool excludeFee = excludedFromFee[from] || excludedFromFee[to];


    //Compute tax amount
    require(tradingEnabled, "Trading is currently disabled");
    uint256 tax =  excludeFee ? 0 : SafeMath.div(SafeMath.mul(amount, basetax), 100);
    uint256 amountAfterTax = amount.sub(tax);
    require(amountAfterTax > 0, "Amount after tax should be positive");   

    if (!excludeFee) {
    ERC20._transfer(from, treasury, tax);
    }
    ERC20._transfer(from, to, amount);
    
   }
   
}
