// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";

import "./ICARROT.sol";

contract CARROT is ICARROT, ERC20, Ownable {
    
    uint8 public basetax = 3;
    uint256 public maxSupply;

    //events
   // event TradingEnabled();
    //event TradingDisabled();

    //safeMathuse
    using SafeMath for uint256;
    
    // a mapping from an address to whether or not it can mint / burn

    mapping(address => bool) public isController;

    // mapping of receivers excluded of the fee

    mapping(address => bool) private excludedFromFee;

    //set defaut trading status to false

    bool public tradingEnabled = false;

    //constructor 

    constructor(uint256 _maxSupply) ERC20("CARROT", "CARROT") 
    {
        maxSupply = _maxSupply;
        _mint(msg.sender, maxSupply);
    }

    receive() external payable {}

    fallback() external payable {}

    //returns totalSupply of the token

    function totalSupply() public view virtual override(IERC20, ERC20) returns (uint256) {
        return ERC20.totalSupply();
    }

    //mints $CARROT to a recipient

    function mint(address to_, uint256 amount_)
        external
        override
        onlyController
    {
        _mint(to_, amount_);
    }

    //burns $CARROT from a holder

    function burn(address from_, uint256 amount_)
        external
        override
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

    //Use ERC20's balanceOf implementation

    function balanceOf(address account_)
        public
        view
        override(ERC20, ICARROT)
        returns (uint256)
    {
        return ERC20.balanceOf(account_);
    }
    //only controllers

    modifier onlyController() {
        if(isController[_msgSender()] == false) revert("CallerNotController");
        _;
    }

    //trading status function 

     function disable_trading() public onlyController{       
        tradingEnabled = false;
        //emit TradingDisabled();
    }

    function enable_trading() public onlyController{
        tradingEnabled = true;
        //emit TradingEnabled();
    }

    //fees functions

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
    require(tradingEnabled, "Trading is currently disabled");
    bool excludeFee = excludedFromFee[from] || excludedFromFee[to];


    // Compute tax amount

    uint256 tax =  excludeFee ? 0 : amount.mul(basetax).div(100);
    uint256 amountAfterTax = amount.sub(tax);
    require(amountAfterTax > 0, "Amount after tax should be positive");   

    if (!excludeFee) {
    ERC20._burn(from, tax);
    }
    ERC20._transfer(from, to, amountAfterTax);
    
   }
   
}
