pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

import "./ERC20.sol";
import "./SafeERC20.sol";

import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./AccessControlEnumerable.sol";
import "./ITheSimpsons.sol";
import "./ERC20PresetMinterRebaser.sol";

contract TheSimpsons is ERC20PresetMinterRebaser, Ownable, ITheSimpsons {
    using SafeMath for uint256;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant MAX_FEE_PER_THOUSAND = 100;    // max fee is 10%
    uint256 constant PRECISION = 1000;

    using SafeMath for uint;

    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) public ammPairs;

    uint256 private _totalFee;

    uint256 public buyTaxFee = 70;   // buy fee per thousand = 7%
    uint256 public sellTaxFee = 100; // sell fee per thousand = 10%
    address public beneficiary;

    /**
     * @dev Guard variable for re-entrancy checks. Not currently used
     */
    bool internal _notEntered;

    /**
     * @notice Internal decimals used to handle scaling factor
     */
    uint256 public constant internalDecimals = 10**24;

    /**
     * @notice Used for percentage maths
     */
    uint256 public constant BASE = 10**18;

    /**
     * @notice Scaling factor that adjusts everyone's balances
     */
    uint256 public scalingFactor;

    mapping(address => uint256) internal _aysBalances;

    mapping(address => mapping(address => uint256)) internal _allowedFragments;

    uint256 public initSupply;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    bytes32 public DOMAIN_SEPARATOR;

    mapping(address => uint256) public nonces;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    uint256 private INIT_SUPPLY = 100_000_000_000 ether;
    uint256 private _totalSupply;

   modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Invalid operator");
        _;
    }
    modifier validRecipient(address to) {
        require(to != address(0x0));
        require(to != address(this));
        _;
    }

    constructor(address _beneficiary) ERC20PresetMinterRebaser("The Simpsons", "SIMPARB") {
        scalingFactor = BASE;
        initSupply = _fragmentToAys(INIT_SUPPLY);
        _totalSupply = INIT_SUPPLY;
        _aysBalances[owner()] = initSupply;       
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        beneficiary = _beneficiary;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, msg.sender);
        emit Transfer(address(0), msg.sender, INIT_SUPPLY);
    }


    fallback () external payable {
        revert(); // Not allow sending native tokem to this contract
    }

    receive() external payable {
        revert(); // Not allow sending native token to this contract
    }

    function _getTaxFee(address sender, address recipient, bool takeFee) private view returns (uint){
        uint _taxFee = 0;
        if(takeFee) {
            bool isBuy = ammPairs[sender];
            bool isSell = ammPairs[recipient];
            if(isBuy) {
                _taxFee = buyTaxFee;
            } else if(isSell){
                _taxFee = sellTaxFee;
            }
        }
        return _taxFee;
    }
    function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee, bool isUnderlaying) private {

        uint _taxFee = _getTaxFee(sender, recipient, takeFee);
        (uint actualAmount, uint fee) = _getValues(amount, _taxFee);
        _doTransfer(sender, recipient, actualAmount, isUnderlaying);

        if(fee > 0) {
            _doTransfer(sender, beneficiary, fee, isUnderlaying);
            _totalFee = _totalFee.add(fee);
            emit FeeDistributedEvent(beneficiary, fee);
        }

    }

   function _doTransfer(address from, address to, uint value, bool isUnderlaying) private {

        if(isUnderlaying) {

            _aysBalances[msg.sender] = _aysBalances[msg.sender].sub(value);

             // add to balance of receiver
            _aysBalances[to] = _aysBalances[to].add(value);
            emit Transfer(msg.sender, to, _aysToFragment(value));

        } else {
            // get value in ays
            uint256 aysValue = _fragmentToAys(value);

            // sub from from
            _aysBalances[from] = _aysBalances[from].sub(aysValue);
            _aysBalances[to] = _aysBalances[to].add(aysValue);
            emit Transfer(from, to, value);
        }
    

   }
    /**
       Calculate actual amount recipient will receive and fee to beneficiary
    */
    function _getValues(uint256 transferAmount, uint taxFee) private pure returns (uint256, uint256) {

        if(taxFee == 0) {
            return (transferAmount, 0);
        }

        uint fee =  transferAmount.mul(taxFee).div(PRECISION);

        uint256 actualAmount = transferAmount.sub(fee, "Fee too high");
        return (actualAmount, fee);
    }


    function isExcludedFromFee(address account) public view returns(bool) {
        return _isExcludedFromFee[account];
    }


    function totalFees() public view returns (uint256) {
        return _totalFee;
    }

    function setTaxFeePercent(uint256 _buyTaxFee, uint256 _sellTaxFee) external onlyOperator {
        require(_buyTaxFee  <= MAX_FEE_PER_THOUSAND, "Buy Tax Fee and Burn fee reached the maximum limit");
        require(_sellTaxFee  <= MAX_FEE_PER_THOUSAND, "Sell Tax Fee and Burn fee reached the maximum limit");
        buyTaxFee = _buyTaxFee;
        sellTaxFee = _sellTaxFee;
        emit NewFeesChangedEvent(buyTaxFee, sellTaxFee);
    }

    function addExcludesFee(address[] calldata accounts) public onlyOperator {
        for(uint i = 0 ; i < accounts.length; i++) {
            _isExcludedFromFee[accounts[i]] = true;
        }
    }

    function removeExcludesFee(address[] calldata accounts) public onlyOperator {
        for(uint i = 0 ; i < accounts.length; i++) {
           delete _isExcludedFromFee[accounts[i]];
        }
    }

    function changeBeneficiary(address newBeneficiary) public onlyOperator {
        beneficiary = newBeneficiary;
    }

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
        // scaling factor can only go up to 2**256-1 = initSupply * scalingFactor
        // this is used to check if scalingFactor will be too high to compute balances when rebasing.
        return uint256(int256(-1)) / initSupply;
    }

    /**
     * @notice Mints new tokens, increasing totalSupply, initSupply, and a users balance.
     */
    function mint(address to, uint256 amount) external returns (bool) {
        require(hasRole(MINTER_ROLE, _msgSender()), "Must have minter role");

        _mint(to, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal override {
        // increase totalSupply
        _totalSupply = _totalSupply.add(amount);

        // get underlying value
        uint256 aysValue = _fragmentToAys(amount);

        // increase initSupply
        initSupply = initSupply.add(aysValue);

        // make sure the mint didnt push maxScalingFactor too low
        require(
            scalingFactor <= _maxScalingFactor(), "max scaling factor too low"
        );

        // add balance
        _aysBalances[to] = _aysBalances[to].add(aysValue);

        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    /**
     * @notice Burns tokens from msg.sender, decreases totalSupply, initSupply, and a users balance.
     */

    function burn(uint256 amount) public override {
        _burn(amount);
    }

    function _burn(uint256 amount) internal {
        // decrease totalSupply
        _totalSupply = _totalSupply.sub(amount);

        // get underlying value
        uint256 aysValue = _fragmentToAys(amount);

        // decrease initSupply
        initSupply = initSupply.sub(aysValue);

        // decrease balance
        _aysBalances[msg.sender] = _aysBalances[msg.sender].sub(aysValue);
        emit Burn(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    /**
     * @notice Mints new tokens using underlying amount, increasing totalSupply, initSupply, and a users balance.
     */
    function mintUnderlying(address to, uint256 amount) public returns (bool) {
        require(hasRole(MINTER_ROLE, _msgSender()), "Must have minter role");

        _mintUnderlying(to, amount);
        return true;
    }

    function _mintUnderlying(address to, uint256 amount) internal {
        // increase initSupply
        initSupply = initSupply.add(amount);

        // get external value
        uint256 scaledAmount = _aysToFragment(amount);

        // increase totalSupply
        _totalSupply = _totalSupply.add(scaledAmount);

        // make sure the mint didnt push maxScalingFactor too low
        require(
            scalingFactor <= _maxScalingFactor(),
            "max scaling factor too low"
        );

        // add balance
        _aysBalances[to] = _aysBalances[to].add(amount);

        emit Mint(to, scaledAmount);
        emit Transfer(address(0), to, scaledAmount);
    }

    /**
     * @dev Transfer underlying balance to a specified address.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @return True on success, false otherwise.
     */
    function transferUnderlying(address to, uint256 value)
        public
        validRecipient(to)
        returns (bool)
    {
         
        _transferUnderly(msg.sender, to, value);
        return true;
    }

    /* - ERC20 functionality - */

    /**
     * @dev Transfer tokens to a specified address.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @return True on success, false otherwise.
     */
    function transfer(address to, uint256 value)
        public
        override
        validRecipient(to)
        returns (bool)
    {
        // underlying balance is stored in ayses, so divide by current scaling factor

        // note, this means as scaling factor grows, dust will be untransferrable.
        // minimum transfer value == scalingFactor / 1e24;

        // get amount in underlying
        // uint256 aysValue = _fragmentToAys(value);

        // // sub from balance of sender
        // _aysBalances[msg.sender] = _aysBalances[msg.sender].sub(aysValue);

        // // add to balance of receiver
        // _aysBalances[to] = _aysBalances[to].add(aysValue);
        // emit Transfer(msg.sender, to, value);

        _transfer(msg.sender, to, value);
        return true;
    }
    function _transfer(address sender, address recipient, uint256 amount) internal override {

        bool takeFee = true;
        if(_isExcludedFromFee[sender] || _isExcludedFromFee[recipient]) {
            takeFee = false;
        }
        _tokenTransfer(sender, recipient, amount, takeFee, false);
    }
    function _transferUnderly(address sender, address recipient, uint256 amount) internal {

        bool takeFee = true;
        if(_isExcludedFromFee[sender] || _isExcludedFromFee[recipient]) {
            takeFee = false;
        }
        _tokenTransfer(sender, recipient, amount, takeFee, true);
    }
    /**
     * @dev Transfer tokens from one address to another.
     * @param from The address you want to send tokens from.
     * @param to The address you want to transfer to.
     * @param value The amount of tokens to be transferred.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override validRecipient(to) returns (bool) {
        // decrease allowance
        _allowedFragments[from][msg.sender] = _allowedFragments[from][msg.sender].sub(value);

        // // get value in ays
        // uint256 aysValue = _fragmentToAys(value);

        // // sub from from
        // _aysBalances[from] = _aysBalances[from].sub(aysValue);
        // _aysBalances[to] = _aysBalances[to].add(aysValue);
        // emit Transfer(from, to, value);
        _transfer(from, to, value);
        return true;
    }

    /**
     * @param who The address to query.
     * @return The balance of the specified address.
     */
    function balanceOf(address who) public view override returns (uint256) {
        return _aysToFragment(_aysBalances[who]);
    }

    /** @notice Currently returns the internal storage amount
     * @param who The address to query.
     * @return The underlying balance of the specified address.
     */
    function balanceOfUnderlying(address who) public view returns (uint256) {
        return _aysBalances[who];
    }

    /**
     * @dev Function to check the amount of tokens that an owner has allowed to a spender.
     * @param owner_ The address which owns the funds.
     * @param spender The address which will spend the funds.
     * @return The number of tokens still available for the spender.
     */
    function allowance(address owner_, address spender)
        public
        view
        override
        returns (uint256)
    {
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
    function approve(address spender, uint256 value)
        public
        override
        returns (bool)
    {
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
    function increaseAllowance(address spender, uint256 addedValue)
        public
        override
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = _allowedFragments[msg.sender][
            spender
        ].add(addedValue);
        emit Approval(
            msg.sender,
            spender,
            _allowedFragments[msg.sender][spender]
        );
        return true;
    }

    /**
     * @dev Decrease the amount of tokens that an owner has allowed to a spender.
     *
     * @param spender The address which will spend the funds.
     * @param subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        override
        returns (bool)
    {
        uint256 oldValue = _allowedFragments[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedFragments[msg.sender][spender] = 0;
        } else {
            _allowedFragments[msg.sender][spender] = oldValue.sub(subtractedValue);
        }
        emit Approval(msg.sender, spender,_allowedFragments[msg.sender][spender]);
        return true;
    }

    // --- Approve by signature ---
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        require(block.timestamp <= deadline, "AYSes/permit-expired");

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender,
                        value,
                        nonces[owner]++,
                        deadline
                    )
                )
            )
        );

        require(owner != address(0), "AYSes/invalid-address-0");
        require(owner == ecrecover(digest, v, r, s), "AYSes/invalid-permit");
        _allowedFragments[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function rebase(
        uint256 epoch,
        uint256 indexDelta,
        bool positive
    ) public returns (uint256) {
        require(hasRole(REBASER_ROLE, _msgSender()), "Must have rebaser role");

        // no change
        if (indexDelta == 0) {
            emit Rebase(epoch, scalingFactor, scalingFactor);
            return _totalSupply;
        }

        // for events
        uint256 prevscalingFactor = scalingFactor;

        if (!positive) {
            // negative rebase, decrease scaling factor
            scalingFactor = scalingFactor
                .mul(BASE.sub(indexDelta))
                .div(BASE);
        } else {
            // positive rebase, increase scaling factor
            uint256 newScalingFactor = scalingFactor
                .mul(BASE.add(indexDelta))
                .div(BASE);
            if (newScalingFactor < _maxScalingFactor()) {
                scalingFactor = newScalingFactor;
            } else {
                scalingFactor = _maxScalingFactor();
            }
        }

        // update total supply, correctly
        _totalSupply = _aysToFragment(initSupply);

        emit Rebase(epoch, prevscalingFactor, scalingFactor);
        return _totalSupply;
    }

    function aysToFragment(uint256 ayses) public view returns (uint256) {
        return _aysToFragment(ayses);
    }

    function fragmentToAys(uint256 value) public view returns (uint256) {
        return _fragmentToAys(value);
    }

    function _aysToFragment(uint256 ayses) internal view returns (uint256) {
        return ayses.mul(scalingFactor).div(internalDecimals);
    }

    function _fragmentToAys(uint256 value) internal view returns (uint256) {
        return value.mul(internalDecimals).div(scalingFactor);
    }

    // Rescue tokens
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) public onlyOwner returns (bool) {
        // transfer to
        SafeERC20.safeTransfer(IERC20(token), to, amount);
        return true;
    }

    function whitelistAmmPairs(address[] calldata ammAddresses) public onlyOperator {

        for(uint i = 0; i < ammAddresses.length; i++) {
            ammPairs[ammAddresses[i]] = true;
        }
    }

     function deListAmmPairs(address[] calldata ammAddresses) public onlyOperator {

        for(uint i = 0; i < ammAddresses.length; i++) {
            ammPairs[ammAddresses[i]] = false;
        }
    }
}
