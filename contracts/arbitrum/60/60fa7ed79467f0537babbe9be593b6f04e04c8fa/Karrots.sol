//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**

             \     /
             \\   //
              )\-/(
              /e e\
             ( =Y= )
             /`-!-'\
        ____/ /___\ \
   \   /    ```    ```~~"--.,_
`-._\ /                       `~~"--.,_
----->|                                `~~"--.,_
_.-'/ \                                         ~~"--.,_
   /   \_________________________,,,,....----""""~~~~````


     88     888    d8P         d8888 8888888b.  8888888b.   .d88888b. 88888888888 
 .d88888b.  888   d8P         d88888 888   Y88b 888   Y88b d88P" "Y88b    888     
d88P 88"88b 888  d8P         d88P888 888    888 888    888 888     888    888     
Y88b.88     888d88K         d88P 888 888   d88P 888   d88P 888     888    888     
 "Y88888b.  8888888b       d88P  888 8888888P"  8888888P"  888     888    888     
     88"88b 888  Y88b     d88P   888 888 T88b   888 T88b   888     888    888     
Y88b 88.88P 888   Y88b   d8888888888 888  T88b  888  T88b  Y88b. .d88P    888     
 "Y88888P"  888    Y88b d88P     888 888   T88b 888   T88b  "Y88888P"     888     
     88                                                                           
                                                                                  
    https://twitter.com/Karrot_gg                                                                    
 */

import "./SafeMath.sol";
import "./ERC20Burnable.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./Context.sol";
import "./AccessControlEnumerable.sol";
import "./Math.sol";
import "./KarrotInterfaces.sol";

/**
Karrots: Rabbits seem to love these tokens can't stop trying to steal them from our users...
- ERC20
- Overrides to support debasing (rebasing)
- Adjustable buy/sell tax
 */

contract Karrots is Context, AccessControlEnumerable, ERC20Burnable, Ownable {
    using SafeMath for uint256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant REBASER_ROLE = keccak256("REBASER_ROLE");

    uint256 public constant PERCENTAGE_DENOMINATOR = 10000;
    uint256 public constant KARROTS_DECIMALS = 1e18;
    uint256 public constant KARROTS_INTERNAL_DECIMALS = 1e24;

    uint256 public constant KARROTS_INIT_SUPPLY = 3324324324357 * KARROTS_DECIMALS;
    uint256 public constant KARROTS_LP_SUPPLY = 1828378378396 * KARROTS_DECIMALS;
    uint256 public constant KARROTS_TEAM_SUPPLY = 332432432435 * KARROTS_DECIMALS;
    uint256 public constant KARROTS_PRESALE_SUPPLY = 1163513513524 * KARROTS_DECIMALS;

    IDexInterfacer public dexInterfacer;
    IConfig public config;

    address public outputAddress;

    bool private isInitialized = false;
    bool public sellTaxIsActive = true;
    bool public buyTaxIsActive = true;
    bool public tradingIsOpen = false;
    bool public transferTradingBlockIsOn = true;

    uint16 public sellTaxRate = 2000; //20-->10-->2%
    uint16 public buyTaxRate = 2000;
    uint64 public karrotsScalingFactor;
    uint160 private _totalSupply;

    uint256 maxIndexDelta = type(uint256).max; //max rebase scale factor increment. setting high for now, can be adjusted later

    ///@notice Scaling factor that adjusts everyone's balances
    mapping(address => uint256) internal _karrotsBalances;
    mapping(address => mapping(address => uint256)) internal _allowedFragments;
    mapping(address => uint256) public nonces;
    mapping(address => bool) public dexAddresses;
    
    event Rebase(uint256 epoch, uint256 prevKarrotsScalingFactor, uint256 newKarrotsScalingFactor);
    event Mint(address to, uint256 amount);
    event Burn(address from, uint256 amount);

    error ForwardFailed();
    error CallerIsNotConfig();
    error TradingIsNotOpen();
    error MaxScalingFactorTooLow();
    error InvalidRecipient();
    error MustHaveMinterRole();
    error MustHaveRebaserRole();
    error OutputAddressNotSet();
    error CallerIsNotStolenPool();

    constructor(address _configManagerAddress) ERC20("Karrot", "KARROT") {
        
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(REBASER_ROLE, _msgSender());
        
        config = IConfig(_configManagerAddress);
        dexInterfacer = IDexInterfacer(config.dexInterfacerAddress());

        karrotsScalingFactor = uint64(KARROTS_DECIMALS);

        _mint(msg.sender, KARROTS_LP_SUPPLY);
        _mint(config.presaleDistributorAddress(), KARROTS_PRESALE_SUPPLY);
        _mint(config.teamSplitterAddress(), KARROTS_TEAM_SUPPLY);

        outputAddress = config.treasuryAddress();
    }

    modifier validRecipient(address to) {
        if(to == address(0x0) || to == address(this)) {
            revert InvalidRecipient();
        }
        _;
    }

    modifier whenTradingIsOpen(address _from) {
        if (
            !tradingIsOpen && 
            _from != config.dexInterfacerAddress() && 
            _from != address(this) &&
            _from != owner()
        )
        {
            revert TradingIsNotOpen();
        }
        _;
    }

    modifier onlyConfig() {
        if (msg.sender != address(config)) {
            revert CallerIsNotConfig();
        }
        _;
    }

    //=========================================================================
    // ERC20 OVERRIDES
    //=========================================================================

    /**
     * @return The total number of fragments.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @notice Computes the current max scaling factor
     */
    function maxScalingFactor() external view returns (uint256) {
        return _maxScalingFactor();
    }

    function _maxScalingFactor() internal view returns (uint256) {
        // scaling factor can only go up to 2**256-1 = _fragmentToKarrots(_totalSupply) * karrotsScalingFactor
        // this is used to check if karrotsScalingFactor will be too high to compute balances when rebasing.
        return uint256(type(uint256).max) / uint256(_fragmentToKarrots(_totalSupply));
    }

    /**
     * @notice Mints new tokens, increasing totalSupply, and a users balance.
     */
    function mint(address to, uint256 amount) external returns (bool) {

        if(!hasRole(MINTER_ROLE, _msgSender())){
            revert MustHaveMinterRole();
        }

        _mint(to, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal override {
        // increase totalSupply
        _totalSupply += uint160(amount);

        // get underlying value
        uint256 karrotsAmount = _fragmentToKarrots(amount);

        // make sure the mint didnt push maxScalingFactor too low
        if(karrotsScalingFactor > _maxScalingFactor()) {
            revert MaxScalingFactorTooLow();
        }

        // add balance
        _karrotsBalances[to] = _karrotsBalances[to].add(karrotsAmount);

        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    /**
     * @notice Burns tokens from msg.sender, decreases totalSupply, and a users balance.
     */

    function burn(uint256 amount) public override {
        _burn(amount);
    }

    function _burn(uint256 amount) internal {
        // decrease totalSupply
        _totalSupply -= uint160(amount);

        // get underlying value
        uint256 karrotsAmount = _fragmentToKarrots(amount);

        // decrease balance
        _karrotsBalances[msg.sender] = _karrotsBalances[msg.sender].sub(karrotsAmount);
        emit Burn(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    //checker for dex addresses
    function isDexAddress(address _addr) internal view returns (bool) {
        return (dexAddresses[_addr]);
    }

    /**
     * @dev Transfer underlying balance to a specified address.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @return True on success, false otherwise.
     */
    function transferUnderlying(address to, uint256 value) public validRecipient(to) returns (bool) {
        // sub from balance of sender
        _karrotsBalances[msg.sender] = _karrotsBalances[msg.sender].sub(value);

        // add to balance of receiver
        _karrotsBalances[to] = _karrotsBalances[to].add(value);
        emit Transfer(msg.sender, to, _karrotsToFragment(value));
        return true;
    }

    /* - ERC20 functionality - */

    /**
     * @dev Transfer tokens to a specified address.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @return True on success, false otherwise.
     */

    function transfer(address to, uint256 value) public override validRecipient(to) returns (bool) {
        // underlying balance is stored in karrots, so divide by current scaling factor

        if(transferTradingBlockIsOn && isDexAddress(msg.sender)){
            revert TradingIsNotOpen();
        }

        // note, this means as scaling factor grows, dust will be untransferrable.
        // minimum transfer value == karrotsScalingFactor / 1e24;
        // get amount in underlying
        address treasuryAddress = config.treasuryAddress();
        uint256 karrotsValue = _fragmentToKarrots(value);

        // sub from balance of sender
        _karrotsBalances[msg.sender] = _karrotsBalances[msg.sender].sub(karrotsValue);
        // [!] applies tax value if applicable
        uint256 thisTaxValue = computeTax(to, value);
        // add to balance of receiver
        _karrotsBalances[to] = _karrotsBalances[to].add(karrotsValue.sub(thisTaxValue));
        // add to balance of treasury
        _karrotsBalances[treasuryAddress] = _karrotsBalances[treasuryAddress].add(thisTaxValue);
        
        emit Transfer(msg.sender, to, value.sub(thisTaxValue));
        emit Transfer(msg.sender, treasuryAddress, thisTaxValue);

        return true;
    }

    /**
     * @dev Transfer tokens from one address to another.
     * @param from The address you want to send tokens from.
     * @param to The address you want to transfer to.
     * @param value The amount of tokens to be transferred.
     */

    function transferFrom(address from, address to, uint256 value) public override validRecipient(to) whenTradingIsOpen(from) returns (bool) {
        // decrease allowance
        _allowedFragments[from][msg.sender] = _allowedFragments[from][msg.sender].sub(value);

        // get value in karrots
        address treasuryAddress = config.treasuryAddress();
        uint256 karrotsValue = _fragmentToKarrots(value);


        uint256 thisTaxValue = computeTax(to, from, value);

        // sub from from
        _karrotsBalances[from] = _karrotsBalances[from].sub(karrotsValue);
        _karrotsBalances[treasuryAddress] = _karrotsBalances[treasuryAddress].add(thisTaxValue);
        _karrotsBalances[to] = _karrotsBalances[to].add(karrotsValue.sub(thisTaxValue));          

        emit Transfer(from, to, value.sub(thisTaxValue));
        emit Transfer(from, treasuryAddress, thisTaxValue);

        return true;
    }

    /**
     * @param who The address to query.
     * @return The balance of the specified address.
     */
    function balanceOf(address who) public view override returns (uint256) {
        return _karrotsToFragment(_karrotsBalances[who]);
    }

    /** @notice Currently returns the internal storage amount
     * @param who The address to query.
     * @return The underlying balance of the specified address.
     */
    function balanceOfUnderlying(address who) public view returns (uint256) {
        return _karrotsBalances[who];
    }

    /**
     * @dev Function to check the amount of tokens that an owner has allowed to a spender.
     * @param owner_ The address which owns the funds.
     * @param spender The address which will spend the funds.
     * @return The number of tokens still available for the spender.
     */
    function allowance(address owner_, address spender) public view override returns (uint256) {
        return _allowedFragments[owner_][spender];
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of
     * msg.sender. This method is included for ERC20 compatibility.
     * increaseAllowance and decreaseAllowance should be used instead.
     * Changing an allowance with this method brings the risk that someone may transfer both
     * the old and the new allowance - if they are both greater than zero - if a transfer
     * transaction is mined before the later approve() call is mined.
     *
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     */
    function approve(address spender, uint256 value) public override returns (bool) {
        _allowedFragments[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @dev Increase the amount of tokens that an owner has allowed to a spender.
     * This method should be used instead of approve() to avoid the double approval vulnerability
     * described above.
     * @param spender The address which will spend the funds.
     * @param addedValue The amount of tokens to increase the allowance by.
     */
    function increaseAllowance(address spender, uint256 addedValue) public override returns (bool) {
        _allowedFragments[msg.sender][spender] = _allowedFragments[msg.sender][spender].add(addedValue);
        emit Approval(msg.sender, spender, _allowedFragments[msg.sender][spender]);
        return true;
    }

    /**
     * @dev Decrease the amount of tokens that an owner has allowed to a spender.
     *
     * @param spender The address which will spend the funds.
     * @param subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public override returns (bool) {
        uint256 oldValue = _allowedFragments[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedFragments[msg.sender][spender] = 0;
        } else {
            _allowedFragments[msg.sender][spender] = oldValue.sub(subtractedValue);
        }
        emit Approval(msg.sender, spender, _allowedFragments[msg.sender][spender]);
        return true;
    }

    function rebase(uint256 epoch, uint256 indexDelta, bool positive) public returns (uint256) {
        if(!hasRole(REBASER_ROLE, _msgSender())) {
            revert MustHaveRebaserRole();
        }
        // no change
        if (indexDelta == 0) {
            emit Rebase(epoch, karrotsScalingFactor, karrotsScalingFactor);
            return _totalSupply;
        }

        //option to add limit to rebase rate, not set by default, likely won't be
        uint256 checkedIndexDelta = Math.min(indexDelta, maxIndexDelta);

        // for events
        uint256 prevKarrotsScalingFactor = karrotsScalingFactor;

        // all rebases should be negative, i.e. scale factor should always decrease and uint64 will hold the scaling factor
        if (!positive) {
            // negative rebase, decrease scaling factor
            karrotsScalingFactor = uint64(Math.mulDiv(uint256(karrotsScalingFactor), KARROTS_DECIMALS, KARROTS_DECIMALS.add(checkedIndexDelta)));
        } else {
            // positive rebase, increase scaling factor
            uint256 newScalingFactor = uint64(Math.mulDiv(uint256(karrotsScalingFactor), KARROTS_DECIMALS.add(checkedIndexDelta), KARROTS_DECIMALS));
            karrotsScalingFactor = uint64(Math.min(uint256(newScalingFactor), _maxScalingFactor()));
        }

        emit Rebase(epoch, prevKarrotsScalingFactor, karrotsScalingFactor);
        return _totalSupply;
    }

    //=========================================================================
    // GETTERS
    //=========================================================================
    // for transfer()
    function computeTax(address _to, uint256 _value) internal view returns (uint256) {
        return computeTax(_to, msg.sender, _value);
    }

    // for transferFrom()
    function computeTax(address _to, address _from, uint256 _value) internal view returns (uint256) {
        //tax applies only on buy and sell events when both buyTax and sellTax are activated
        if(_from == owner()) {
            return 0;
        }
        
        if (sellTaxIsActive && isDexAddress(_to)) {
            return _value.mul(sellTaxRate).div(PERCENTAGE_DENOMINATOR);
        } else if (buyTaxIsActive && isDexAddress(_from)) {
            return _value.mul(buyTaxRate).div(PERCENTAGE_DENOMINATOR);
        } else {
            return 0;
        }
    }

    function karrotsToFragment(uint256 karrots) public view returns (uint256) {
        return _karrotsToFragment(karrots);
    }

    function fragmentToKarrots(uint256 fragment) public view returns (uint256) {
        return _fragmentToKarrots(fragment);
    }

    function _karrotsToFragment(uint256 karrots) internal view returns (uint256) {
        return karrots.mul(karrotsScalingFactor).div(KARROTS_INTERNAL_DECIMALS);
    }

    function _fragmentToKarrots(uint256 value) internal view returns (uint256) {
        return value.mul(KARROTS_INTERNAL_DECIMALS).div(karrotsScalingFactor);
    }

    function getTotalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    //=========================================================================
    // SETTERS
    //=========================================================================

    function setConfigManagerAddress(address _configManager) external onlyOwner {
        config = IConfig(_configManager);
    }

    function setSellTaxRate(uint16 _sellTaxRate) external onlyConfig {
        sellTaxRate = _sellTaxRate;
    }

    function setBuyTaxRate(uint16 _buyTaxRate) external onlyConfig {
        buyTaxRate = _buyTaxRate;
    }

    function setSellTaxIsActive(bool _sellTaxIsActive) external onlyConfig {
        sellTaxIsActive = _sellTaxIsActive;
    }

    function setBuyTaxIsActive(bool _buyTaxIsActive) external onlyConfig {
        buyTaxIsActive = _buyTaxIsActive;
    }

    function setTradingIsOpen(bool _tradingIsOpen) external onlyConfig {
        tradingIsOpen = _tradingIsOpen;
    }

    function addDexAddress(address _addr) external onlyConfig {
        dexAddresses[_addr] = true;
    }

    function removeDexAddress(address _addr) external onlyConfig {
        dexAddresses[_addr] = false;
    }

    function setMaxIndexDelta(uint256 _maxIndexDelta) external onlyConfig {
        maxIndexDelta = _maxIndexDelta;
    }

    function setTransferTradingBlockIsOn(bool _transferTradingBlockIsOn) external onlyConfig {
        transferTradingBlockIsOn = _transferTradingBlockIsOn;
    }

    //=========================================================================
    // WITHDRAWALS
    //=========================================================================

    function setOutputAddress(address _outputAddress) external onlyOwner {
        outputAddress = _outputAddress;
    }

    function withdrawERC20FromContract(address _to, address _token) external onlyOwner {
        bool os = IERC20(_token).transfer(_to, IERC20(_token).balanceOf(address(this)));
        if (!os) {
            revert ForwardFailed();
        }
    }

    function withdrawEthFromContract() external onlyOwner {
        if(outputAddress == address(0)){
            revert OutputAddressNotSet();
        }

        (bool os, ) = payable(outputAddress).call{value: address(this).balance}("");
        if (!os) {
            revert ForwardFailed();
        }
    }
}

