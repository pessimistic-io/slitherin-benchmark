// SPDX-License-Identifier: MIT
 
pragma solidity 0.8.15;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./ITEST.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}
 
interface IUniswapV2Router02 {
 
    function factory() external pure returns (address);

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
    
    uint256 private initialSupply;
    uint256 public maxSupply;
    

    //SafeMathuse

    using SafeMath for uint256;
    
    //Mapping from an address to whether or not it can mint / burn

    mapping(address => bool) private isController;

    //Set defaut trading status to false

    bool public tradingEnabled = false;

    //Constructor 

    constructor(uint256 _initialSupply , uint256 _maxSupply) ERC20("TEST", "TEST") 
    {
        initialSupply = _initialSupply;
        maxSupply = _maxSupply;
        _mint(msg.sender, initialSupply);
    }

    //Mints $TEST to a recipient

    function mint(address to_, uint256 amount_)
        external
        override
        onlyController
    {
        require(totalSupply().add(amount_) <= maxSupply, "Maximum supply reached");
        _mint(to_, amount_);
    }

    //Burns $TEST from a holder

    function burn(address from_, uint256 amount_)
        external
        override
        onlyController
    {
        _burn(from_, amount_);
    }

    event ControllerAdded(address newController);

    //Enables an address to mint / burn
      
    
    function addController(address toAdd_) external onlyOwner {
        isController[toAdd_] = true;
        emit ControllerAdded(toAdd_);
    }

    event ControllerRemoved(address controllerRemoved);

    //Disable an address to mint / burn

    function removeController(address toRemove_) external onlyOwner {
        isController[toRemove_] = false;
        emit ControllerRemoved(toRemove_);
    }

    //Only controllers

    modifier onlyController() {
        if(isController[_msgSender()] == false) revert("CallerNotController");
        _;
    }

    //Trading status function 

     function pause_trading() public onlyOwner{       
        tradingEnabled = false;
    }

    function enable_trading() public onlyOwner{
        tradingEnabled = true;
    }

    //Transfer function

    function _transfer(
    address from,
    address to,
    uint256 amount
    
    ) internal override {
    require(tradingEnabled, "Trading is currently disabled");

    ERC20._transfer(from, to, amount);
    
   }
   
}
