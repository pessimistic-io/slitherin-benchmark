// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./ITEST.sol";

contract TEST is ITEST, ERC20, Ownable {
    
    uint256 public maxSupply;
    uint256 private initialSupply;

    //safeMathuse
    using SafeMath for uint256;
    
    // a mapping from an address to whether or not it can mint / burn

    mapping(address => bool) public isController;


    //set defaut trading status to false

    bool public tradingEnabled = false;

    //constructor 

    constructor(uint256 _initialSupply , uint256 _maxSupply) ERC20("TEST", "TEST") 
    {
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


    //transfer function
    function _transfer(
    address from,
    address to,
    uint256 amount
    
    ) internal override {
    require(tradingEnabled, "Trading is currently disabled");
    ERC20._transfer(from, to, amount);
    
   }
   
}
