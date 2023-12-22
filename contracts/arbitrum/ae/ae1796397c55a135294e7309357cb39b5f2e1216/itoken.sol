// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";

contract itoken is ERC20 {
    
    uint8 private _decimals;

    address public daaaddress;
    mapping(address =>bool) public whitelistedaddress;
    mapping(address =>bool) public managerAddress;

        /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * To select a different value for {decimals}, use {_setupDecimals}.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
   constructor (string memory name_, string memory symbol_, uint8 decimals_, address daaaddress_, address managerAddress_, address chefAddress_)ERC20(name_, symbol_) {
        _decimals = decimals_;
        daaaddress = daaaddress_;
        managerAddress[managerAddress_] = true;
        managerAddress[msg.sender] = true;
        addChefAddress(chefAddress_);
    }


    function mint(address to, uint256 amount) external {
        require(msg.sender == daaaddress, "itoken::mint:Only daa can mint");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == daaaddress, "itoken::burn:Only daa can burn");
        _burn(from, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override
    {
        if(msg.sender != daaaddress){
            require(validateTransaction(from,to),"itoken::transfer: Can only be traded with DAA pool/chef");
        }
        super._beforeTokenTransfer(from, to, amount);
    }

        /**
     * @dev Check if itoken can be transfered between the sender and reciepents.
     * Only whitelisted address has permission like DAA contract/chef contract.
     */

    function validateTransaction(address to, address from) public view returns(bool){
        if(whitelistedaddress[to] || whitelistedaddress[from]){
            return true;
        }
        else{
            return false;
        }
    }

    /**
     * @dev Add Chef address so that itoken can be deposited/withdraw from 
     * @param _address Address of Chef contract
     */
    function addChefAddress(address _address) public returns(bool){
        require(managerAddress[msg.sender],"Only manager can add address");
        require(_address != address(0), "Zero Address");
        require(!whitelistedaddress[_address],"Already white listed");
        whitelistedaddress[_address] = true;
        return true;
    }

    function decimals() override public view returns (uint8) {
        return _decimals;
    }
}

contract itokendeployer is Ownable{
    using SafeMath for uint256;

    // DAA contract address
    address public daaaddress;
    // Chef contract address
    address public chefAddress;
    // List of deployed itokens
    address[] public deployeditokens;
    // Total itoken.
    uint256 public totalItokens;

    uint8 public decimalValue;

    /**
     * @dev Modifier to check if the caller is daa contract or not
     */
    modifier onlyDaa{
        require(msg.sender == daaaddress, "Only DAA contract can call");
        _;
    }
    /**
     * @dev Constructor.
     */
    constructor() public {
        decimalValue = 6;
	}

    /**
     * @dev Create new itoken when a new pool is created. Mentioned in Public Facing ASTRA TOKENOMICS document  itoken distribution 
       section that itoken need to be given a user for deposit in pool.
     * @param _name name of the token
     * @param _symbol symbol of the token, 3-4 chars is recommended
     */
    function createnewitoken(string calldata _name, string calldata _symbol) external onlyDaa returns(address) {
		itoken _itokenaddr = new itoken(_name, _symbol, decimalValue, msg.sender, owner(), chefAddress);  
        deployeditokens.push(address(_itokenaddr));
        totalItokens = totalItokens.add(1);
		return address(_itokenaddr);  
	}

    /**
     * @dev Get the address of the itoken based on the pool Id.
     * @param pid Daa Pool Index id.
     */
    function getcoin(uint256 pid) external view returns(address){
        return deployeditokens[pid];
    }

    /**
     * @dev Add the address DAA pool configurtaion contrac so that only Pool contract can create the itokens.
     * @param _address Address of the DAA contract.
     */
    function addDaaAdress(address _address) public onlyOwner { 
        require(_address != address(0), "Zero Address");
        require(daaaddress != _address, "Already set Daa address");
	    daaaddress = _address;
	}

    /**
     * @dev Add the address of the Chef contract so that Chef contract can be whitelisted.
     * @param _address Address of the Chef contract.
     */
    function addChefAddress(address _address) public onlyOwner { 
        require(_address != address(0), "Zero Address");
        require(chefAddress != _address, "Already set Chef address");   
        chefAddress = _address;
    }

    /**
     * @dev Update decimal value for itoken.
     * @param _decimalValue New decimal value.
     */
    function updateDecimalValue(uint8 _decimalValue) public onlyOwner { 
        decimalValue = _decimalValue;
	}
    
}
