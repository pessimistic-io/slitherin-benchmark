// SPDX-License-Identifier: MIT
/*
██████╗ ███████╗███████╗██╗    ███████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗
██╔══██╗██╔════╝██╔════╝██║    ██╔════╝╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔════╝████╗ ████║
██║  ██║█████╗  █████╗  ██║    ███████╗ ╚████╔╝ ███████╗   ██║   █████╗  ██╔████╔██║
██║  ██║██╔══╝  ██╔══╝  ██║    ╚════██║  ╚██╔╝  ╚════██║   ██║   ██╔══╝  ██║╚██╔╝██║
██████╔╝███████╗██║     ██║    ███████║   ██║   ███████║   ██║   ███████╗██║ ╚═╝ ██║
╚═════╝ ╚══════╝╚═╝     ╚═╝    ╚══════╝   ╚═╝   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝

███████╗ ██████╗ ██████╗     ██████╗ ███████╗███████╗███████╗██████╗ ███████╗███╗   ██╗ ██████╗███████╗
██╔════╝██╔═══██╗██╔══██╗    ██╔══██╗██╔════╝██╔════╝██╔════╝██╔══██╗██╔════╝████╗  ██║██╔════╝██╔════╝
█████╗  ██║   ██║██████╔╝    ██████╔╝█████╗  █████╗  █████╗  ██████╔╝█████╗  ██╔██╗ ██║██║     █████╗
██╔══╝  ██║   ██║██╔══██╗    ██╔══██╗██╔══╝  ██╔══╝  ██╔══╝  ██╔══██╗██╔══╝  ██║╚██╗██║██║     ██╔══╝
██║     ╚██████╔╝██║  ██║    ██║  ██║███████╗██║     ███████╗██║  ██║███████╗██║ ╚████║╚██████╗███████╗
╚═╝      ╚═════╝ ╚═╝  ╚═╝    ╚═╝  ╚═╝╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝ ╚═════╝╚══════╝
Version 2.0
Developed by the same team of systemdefi.crypto, rsd.cash and timetoken.finance
Integrates TIME Token and some of its contracts with RSD + SDR system
---------------------------------------------------------------------------------------

REVERT/REQUIRE CODE ERRORS:
DSRv2_01: please refer you can call this function only once at a time until it is fully executed
DSRv2_02: you should allow D2 to be spent before calling the function
DSRv2_03: TIME amount sent must match with the ETH amount sent
DSRv2_04: D2 contract does not have enough ETH amount to perform the operation
DSRv2_05: the pool does not have a sufficient amount to trade
DSRv2_06: there is no enough tokens to sell
DSRv2_07: there is no enough tokens to burn
DSRv2_08: only D2Helper can call this function
DSRv2_09: get out of here dude!
DSRv2_10: borrowed amount must be less or equal to total supply
DSRv2_11: not enough to cover expenses
DSRv2_12: please do not forget to call payFlashMintFee() function and pay the flash mint
---------------------------------------------------------------------------------------
*/
pragma solidity ^0.8.10;

import "./IERC20.sol";
import "./Ownable.sol";
import "./Math.sol";
import "./OFT.sol";
import "./AggregatorV3Interface.sol";
import "./ID2HelperBase.sol";
import "./IEmployer.sol";
import "./IReferenceSystemDeFi.sol";
import "./ITimeToken.sol";
import "./ID2FlashMintBorrower.sol";

contract DeFiSystemReferenceV2Final is Ownable, OFT {
    using Math for uint256;

    bool private _isFlashMintPaid;
    bool private _isFlashMintStarted;
    bool private _isOperationLocked;

    address private constant DONATION_ADDRESS = 0xbF616B8b8400373d53EC25bB21E2040adB9F927b;

    address payable private immutable _employerAddress;

    string private _name;
    string private _symbol;

    uint256 private constant FACTOR = 10 ** 18;
    uint256 private constant CHAINLINK_FACTOR = 10 ** 8;
    uint256 private constant SPLIT_SHARES = 7;
    uint256 private constant MINT_SHARES = 5;
    uint256 private constant COMISSION_RATE = 100;
    uint256 private constant DONATION_RATE = 50;

    uint256 private _arbitrageCount;
    uint256 private _currentBlockTryPoBet;
    uint256 private _currentFlashMintFee;
    uint256 private _dividendPerToken;
    uint256 private _totalSupply;
    uint256 private _totalForDividend;

    uint256 public constant FLASH_MINT_FEE = 100;

    uint256 public poolBalance;
    uint256 public toBeShared;
    uint256 public totalEarned;
    uint256 public totalEarnedFromFlashMintFee;

    ITimeToken private timeToken;
    IReferenceSystemDeFi private rsd;
    AggregatorV3Interface private chainlink;

    ID2HelperBase public d2Helper;

    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _consumedDividendPerToken;

    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(
        string memory name_,
        string memory symbol_,
        address _d2HelperAddress,
        address employerAddress_,
        address _timeTokenAddress,
        address _rsdTokenAddress,
        address _lzEndPointAddress,
        address _chainlinkAddress,
        address _owner
    ) OFT(name_, symbol_, _lzEndPointAddress) {
        _name = name_;
        _symbol = symbol_;
        _employerAddress = payable(employerAddress_);
        timeToken = ITimeToken(payable(_timeTokenAddress));
        rsd = IReferenceSystemDeFi(_rsdTokenAddress);
        d2Helper = ID2HelperBase(_d2HelperAddress);
        chainlink = AggregatorV3Interface(_chainlinkAddress);
        transferOwnership(_owner);
    }

    /**
     * @dev This modifier is called when a flash mint is performed. It modifies the internal state of the contract to avoid share calculation when flash mint is running
     *
     */
    modifier performFlashMint() {
        require(!_isFlashMintStarted, "DSRv2_09");
        _isFlashMintPaid = false;
        _isFlashMintStarted = true;
        _;
        _isFlashMintStarted = false;
    }

    /**
     * @dev This modifier helps to avoid/mitigate reentrancy attacks
     *
     */
    modifier nonReentrant() {
        require(!_isOperationLocked || msg.sender == address(d2Helper), "DSRv2_01");
        _isOperationLocked = true;
        _;
        _isOperationLocked = false;
    }

    /**
     * @dev Performs state update when receiving funds from any source
     *
     */
    receive() external payable {
        _receive();
    }

    /**
     * @dev Fallback function to call in any situation
     *
     */
    fallback() external payable {
        require(msg.data.length == 0 || msg.sender == address(timeToken) || msg.sender == address(d2Helper));
        _receive();
    }

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     */
    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        _tryPoBet(uint256(sha256(abi.encodePacked(from, to, amount))));
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        _credit(from);
        _credit(to);
    }

    /**
     * @dev Add liquidity for the D2/ETH pair LP in third party exchange (based on UniswapV2)
     * @param amount The amount in ETH to add to the LP
     * @param d2Amount The amount in D2 to add to the LP
     *
     */
    function _addLiquidityD2Native(uint256 amount, uint256 d2Amount) private {
        require(address(this).balance >= amount, "DSRv2_04");
        if (d2Amount > 0) {
            address d2HelperAddress = address(d2Helper);
            _mint(d2HelperAddress, d2Amount);
            bool success = d2Helper.addLiquidityD2Native{ value: amount }(d2Amount);
            if (!success && _balances[d2HelperAddress] > 0) {
                _burn(d2HelperAddress, _balances[d2HelperAddress]);
                _mint(address(this), d2Amount);
            }
        }
    }

    /**
     * @dev Add liquidity for the D2/SDR pair LP in third party exchange (based on UniswapV2)
     * @param d2Amount The amount in D2 to add to the LP
     *
     */
    function _addLiquidityD2Sdr(uint256 d2Amount) private {
        if (d2Amount > 0) {
            address d2HelperAddress = address(d2Helper);
            _mint(d2HelperAddress, d2Amount);
            try d2Helper.addLiquidityD2Sdr() returns (bool success) {
                if (!success && _balances[d2HelperAddress] > 0) {
                    _burn(d2HelperAddress, _balances[d2HelperAddress]);
                }
            } catch { }
        }
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual override {
        require(owner != address(0), "ERC20 D2: approve from the zero address");
        require(spender != address(0), "ERC20 D2: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual override {
        require(account != address(0), "ERC20 D2: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20 D2: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Use part of the funds to generate value for TIME Token, buying some amount
     * @param amount The amount to buy
     */
    function _buyAndBurnTime(uint256 amount) private {
        require(address(this).balance >= amount, "DSRv2_04");
        address(timeToken).call{ value: amount }("");
        timeToken.burn(timeToken.balanceOf(address(this)));
    }

    /**
     * @dev Use part of the funds to generate value for the RSD and SDR tokens. Also, it provides external liquidity to the D2/SDR pair
     * @param amount The amount used to buy RSD first
     *
     */
    function _buyRsdSdrAndAddLiquidity(uint256 amount) private {
        require(address(this).balance >= amount, "DSRv2_04");
        try d2Helper.buyRsd{ value: amount }() {
            try d2Helper.buySdr() {
                _addLiquidityD2Sdr(_queryD2AmountOptimal(amount));
            } catch { }
        } catch { }
    }

    /**
     * @dev Calculate comission value over the provided amount
     * @return uint256 Comission value
     *
     */
    function _calculateComissionOverAmount(uint256 amount) private pure returns (uint256) {
        return amount.mulDiv(COMISSION_RATE, 10_000);
    }

    /**
     * @dev Check for arbitrage opportunities and perform them if they are profitable. Profit is shared with D2 token holders
     *
     */
    function _checkAndPerformArbitrage() private {
        try d2Helper.checkAndPerformArbitrage() returns (bool success) {
            if (success) {
                _arbitrageCount++;
            }
        } catch { }
    }

    /**
     * @dev Calculate the amount some address has to claim and credit for it
     * @param account The account address
     *
     */
    function _credit(address account) private {
        uint256 amount = accountShareBalance(account);
        if (amount > 0) {
            _balances[account] += amount;
            emit Transfer(address(0), account, amount);
        }
        _consumedDividendPerToken[account] = _dividendPerToken;
    }

    /**
     * @dev Send ETH to the Employer as reward to investors
     * @param amount Value to send to the Employer
     */
    function _feedEmployer(uint256 amount) private {
        require(address(this).balance >= amount, "DSRv2_04");
        _employerAddress.call{ value: amount }("");
    }

    /**
     * @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual override {
        require(account != address(0), "ERC20 D2: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _totalForDividend += (account != address(d2Helper) && account != address(this)) ? amount : 0;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev It creates and returns a random address
     * @param someNumber Used as seed number to improve randomness
     *
     */
    function _obtainRandomWalletAddress(uint256 someNumber) private view returns (address) {
        return address(bytes20(sha256(abi.encodePacked(toBeShared, _totalForDividend, someNumber))));
    }

    /**
     * @dev Returns the optimal amount, in terms of D2 tokens, for the native amount passed
     * @param amountNative The native amount to be converted
     * @return uint256 The D2 optimal amount from native amount informed
     *
     */
    function _queryD2AmountOptimal(uint256 amountNative) private view returns (uint256) {
        uint256 externalLP = queryD2AmountExternalLP(amountNative);
        uint256 internalLP = queryD2AmountInternalLP(amountNative);
        if (externalLP >= internalLP) {
            return (msg.sender == address(d2Helper)) ? externalLP : internalLP;
        } else {
            return (msg.sender == address(d2Helper)) ? internalLP : externalLP;
        }
    }

    /**
     * @dev Returns the native amount for the amount of D2 tokens passed
     * @param d2Amount The amount of D2 tokens to be converted
     * @return uint256 The amount of native tokens correspondent to the D2 tokens amount
     *
     */
    function _queryNativeAmount(uint256 d2Amount) private view returns (uint256) {
        return d2Amount.mulDiv(queryPriceInverse(d2Amount), FACTOR);
    }

    /**
     * @dev Private receive function. Called when the external receive() or fallback() functions receive funds
     *
     */
    function _receive() private {
        totalEarned += msg.value;
        toBeShared += msg.value;
        _updatePoolBalance();
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual override {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20 D2: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /**
     * @dev Private function called when the system needs to split shares among D2 holders
     * @notice SPLIT_SHARES:
     *   1. msg.sender - D2 minted | LP Internal
     *   2. Buy TIME + RSD
     *   3. Employer Feed
     *   4. LP External 
     *   5. LP Internal 
     *   6. Dividends | LP Internal
     *   7. Donation Address
     */
    function _splitSharesDinamically(bool forLiquidity) private {
        uint256 share = toBeShared / (forLiquidity ? SPLIT_SHARES + 2 : SPLIT_SHARES);
        if (forLiquidity)
            _mintForLiquidity(share);

        if (address(rsd) != address(0)) {
            _buyAndBurnTime(share / 2);
            _buyRsdSdrAndAddLiquidity(share / 2);
        } else {
            _buyAndBurnTime(share);
        }
        _feedEmployer(share);
        payable(DONATION_ADDRESS).call{ value: share }("");

        // Calculates dividend to be shared among D2 holders and add it to the total supply
        uint256 currentDividend = _dividendPerToken;
        _dividendPerToken += queryD2AmountInternalLP(share).mulDiv(FACTOR, _totalForDividend);
        uint256 t = _totalForDividend.mulDiv(_dividendPerToken - currentDividend, FACTOR);
        _totalSupply += t;
        _totalForDividend += t;

        toBeShared = 0;
        _checkAndPerformArbitrage();
        _updatePoolBalance();
    }    

    /**
     * @dev Moves `amount` of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
    function _transfer(address from, address to, uint256 amount) internal virtual override {
        require(from != address(0), "ERC20 D2: transfer from the zero address");
        require(to != address(0), "ERC20 D2: transfer to the zero address");

        _checkAndPerformArbitrage();

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20 D2: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    /**
     * @dev Tries to earn some RSD tokens in the PoBet system. The earned amount is exchanged with SDR, which is then locked in D2/SDR LP
     * @param someNumber Seed number to improve randomness
     */
    function _tryPoBet(uint256 someNumber) private {
        if (_currentBlockTryPoBet != block.number && address(rsd) != address(0)) {
            _currentBlockTryPoBet = block.number;
            uint256 rsdBalance = rsd.balanceOf(address(this));
            try rsd.transfer(_obtainRandomWalletAddress(someNumber), rsdBalance) {
                uint256 newRsdBalance = rsd.balanceOf(address(this));
                // it means we have won the PoBet prize! Woo hoo! So, now we exchange RSD for SDR with this earned amount!
                if (rsdBalance < newRsdBalance || rsd.balanceOf(address(d2Helper)) > 0) {
                    rsd.transfer(address(d2Helper), newRsdBalance);
                    try d2Helper.buySdr() {
                        _addLiquidityD2Sdr(d2Helper.queryD2AmountFromSdr());
                    } catch { }
                }
            } catch { }
        }
    }

    /**
     * @dev Updates the state of the internal pool balance
     *
     */
    function _updatePoolBalance() private {
        poolBalance = address(this).balance > toBeShared ? address(this).balance - toBeShared : 0;
    }

    /**
     * @dev Returns the number of times an arbitrage was made
     */
    function arbitrageCount() external view returns (uint256) {
        return _arbitrageCount;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account] + accountShareBalance(account);
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (to == address(this)) {
            sellD2(amount);
        } else {
            _transfer(msg.sender, to, amount);
        }
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual override returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual override returns (bool) {
        address owner = msg.sender;
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20 D2: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Show the amount an account address can credit to itself
     * @notice Shares are not calculated when running flash mint
     * @param account The address of some account
     * @return The claimable amount
     *
     */
    function accountShareBalance(address account) public view returns (uint256) {
        if (account != address(this) && account != d2Helper.pairD2Eth() && account != d2Helper.pairD2Sdr()
                && account != address(d2Helper) && !_isFlashMintStarted
        ) {
            return _balances[account].mulDiv(_dividendPerToken - _consumedDividendPerToken[account], FACTOR);
        } else {
            return 0;
        }
    }

    /**
     * @dev External function to burn D2 tokens. Sometimes is useful when you want to throw your money away... Who knows?
     * @param amount The amount of D2 tokens to be burned
     *
     */
    function burn(uint256 amount) external {
        require(amount <= balanceOf(msg.sender), "DSRv2_07");
        _burn(msg.sender, amount);
    }

    /**
     * @dev Main function of the D2 contract. Called whenever someone needs to generate tokens under the required conditions
     * @param timeAmount The amount of TIME Tokens an investor wants to use in order to mint more D2 tokens
     *
     */
    function mintD2(uint256 timeAmount) external payable nonReentrant {
        // It must burn TIME Token in order to mint additional D2 tokens
        require(timeToken.allowance(msg.sender, address(this)) >= timeAmount, "DSRv2_02");
        uint256 timeAmountNativeValue = queryNativeFromTimeAmount(timeAmount);
        require(msg.value >= timeAmountNativeValue && msg.value > 0, "DSRv2_03");
        if (timeAmount > 0) {
            timeToken.transferFrom(msg.sender, address(this), timeAmount);
            timeToken.burn(timeAmount);
        }
        uint256 share = msg.value / MINT_SHARES;
        _mintForLiquidity(share.mulDiv(15, 10));
        _mint(msg.sender, queryD2AmountOptimal(share + timeAmountNativeValue));
        d2Helper.kickBack{ value: share }();
        _splitSharesDinamically(false);
    }

    /**
    * @dev Performs D2 minting for Liquidity Pools (Internal and External)
    * @notice It should query Chainlink to check the USD rate/price of native currency in order to maintain the same rate on all deployed networks
    * @param share The amount of ETH dedicated for the pools
    **/
    function _mintForLiquidity(uint256 share) private {
        uint256 d2ShareForLiquidity = _queryD2AmountOptimal(share);
        if (d2ShareForLiquidity == share) {
            (, int256 roundData,,,) = chainlink.latestRoundData();
            d2ShareForLiquidity = d2ShareForLiquidity.mulDiv(uint256(roundData), CHAINLINK_FACTOR);
        }
        _addLiquidityD2Native(share, d2ShareForLiquidity);
        _mint(address(this), d2ShareForLiquidity);
    }

    /**
     * @dev Queries for the external amount, in terms of D2 tokens, given an informed native amount
     * @notice It queries for the external LP
     * @param amountNative The native amount
     * @return uint256 The amount of D2 tokens
     *
     */
    function queryD2AmountExternalLP(uint256 amountNative) public view returns (uint256) {
        uint256 d2AmountExternalLP = amountNative.mulDiv(d2Helper.queryD2Rate(), FACTOR);
        return (d2AmountExternalLP == 0) ? amountNative : d2AmountExternalLP;
    }

    /**
     * @dev Queries for the internal amount, in terms of D2 tokens, given an informed native amount
     * @notice It queries for the internal LP
     * @param amountNative The native amount
     * @return uint256 The amount of D2 tokens
     *
     */
    function queryD2AmountInternalLP(uint256 amountNative) public view returns (uint256) {
        uint256 d2AmountInternalLP = amountNative.mulDiv(queryPriceNative(amountNative), FACTOR);
        return (d2AmountInternalLP == 0) ? amountNative : d2AmountInternalLP;
    }

    /**
     * @dev Queries for the optimal amount, in terms of D2 tokens, given an informed native amount
     * @param amountNative The native amount
     * @return uint256 The amount of D2 tokens
     *
     */
    function queryD2AmountOptimal(uint256 amountNative) public view returns (uint256) {
        uint256 d2AmountOptimal = _queryD2AmountOptimal(amountNative);
        return (d2AmountOptimal - _calculateComissionOverAmount(d2AmountOptimal));
    }

    /**
     * @dev Queries for the native amount value given some D2 tokens informed
     * @param d2Amount The amount of D2 tokens
     * @return uint256 The native amount
     *
     */
    function queryNativeAmount(uint256 d2Amount) external view returns (uint256) {
        uint256 d2AmountNativeValue = _queryNativeAmount(d2Amount);
        return (d2AmountNativeValue - _calculateComissionOverAmount(d2AmountNativeValue));
    }

    /**
     * @dev Queries for the native amount value given some TIME Token amount passed
     * @param timeAmount The amount of TIME Tokens informed
     * @return uint256 The native amount
     *
     */
    function queryNativeFromTimeAmount(uint256 timeAmount) public view returns (uint256) {
        if (timeAmount != 0) {
            return timeAmount.mulDiv(timeToken.swapPriceTimeInverse(timeAmount), FACTOR);
        } else {
            return 0;
        }
    }

    /**
     * @dev Query for market price before swap, in D2/ETH, in terms of native cryptocurrency (ETH)
     * @notice Constant Function Market Maker
     * @param amountNative The amount of ETH a user wants to exchange
     * @return Local market price, in D2/ETH, given the amount of ETH a user informed
     *
     */
    function queryPriceNative(uint256 amountNative) public view returns (uint256) {
        if (poolBalance > 0 && _balances[address(this)] > 0) {
            uint256 ratio = poolBalance.mulDiv(FACTOR, amountNative + 1);
            uint256 deltaSupply =
                _balances[address(this)].mulDiv(amountNative.mulDiv(ratio, 1), poolBalance + amountNative);
            return deltaSupply / poolBalance;
        } else {
            return FACTOR;
        }
    }

    /**
     * @dev Query for market price before swap, in ETH/D2, in terms of ETH currency
     * @param d2Amount The amount of D2 a user wants to exchange
     * @return Local market price, in ETH/D2, given the amount of D2 a user informed
     *
     */
    function queryPriceInverse(uint256 d2Amount) public view returns (uint256) {
        if (poolBalance > 0 && _balances[address(this)] > 0) {
            uint256 deltaBalance = poolBalance.mulDiv(d2Amount.mulDiv(_balances[address(this)].mulDiv(FACTOR, d2Amount + 1), 1), _balances[address(this)] + d2Amount);
            return deltaBalance / _balances[address(this)];
        } else {
            return 1;
        }
    }

    /**
     * @dev Queries the amount to be paid to callers of the splitSharesDinamicallyWithReward() function
     * @return uint256 The amount to be paid
     *
     */
    function queryPublicReward() public view returns (uint256) {
        return toBeShared.mulDiv(DONATION_RATE, 10_000);
    }

    /**
     * @dev Returns native amount back to the D2 contract when it is not desired to share the amount with holders. Usually called by D2Helper
     * @return bool Just a silly response
     *
     */
    function returnNativeWithoutSharing() external payable nonReentrant returns (bool) {
        _updatePoolBalance();
        return true;
    }

    /**
     * @dev Splits the share (earned amount) among the D2 token holders and pays a reward for the caller
     * @notice This function should be called sometimes in order to make the contract works as desired
     *
     */
    function splitSharesDinamicallyWithReward() external nonReentrant {
        if (toBeShared > 0) {
            uint256 reward = queryPublicReward();
            toBeShared -= reward;
            _splitSharesDinamically(true);
            payable(msg.sender).transfer(reward);
            _updatePoolBalance();
        }
    }

    /**
     * @dev Investor send native cryptocurrency in exchange for D2 tokens. Here, he sends some amount and the contract calculates the equivalent amount in D2 units
     * @notice msg.value - The amount of D2 in terms of ETH an investor wants to buy
     * @return success If the operation was performed well
     */
    function buyD2() external payable nonReentrant returns (bool success) {
        if (msg.value > 0) {
            uint256 nativeAmountD2Value = _queryD2AmountOptimal(msg.value);
            require(nativeAmountD2Value <= _balances[address(this)], "DSRv2_05");
            if (msg.sender == address(d2Helper)) {
                _transfer(address(this), msg.sender, nativeAmountD2Value);
            } else {
                _transfer(
                    address(this), msg.sender, nativeAmountD2Value - _calculateComissionOverAmount(nativeAmountD2Value)
                );
            }
            _updatePoolBalance();
            success = true;
        }
        return success;
    }

    /**
     * @dev Investor send D2 tokens in exchange for native cryptocurrency
     * @param d2Amount The amount of D2 tokens for exchange
     * @return success Informs if the sell was performed well
     */
    function sellD2(uint256 d2Amount) public nonReentrant returns (bool success) {
        require(!_isFlashMintStarted, "DSRv2_09");
        require(balanceOf(msg.sender) >= d2Amount, "DSRv2_06");
        uint256 d2AmountNativeValue = _queryNativeAmount(d2Amount);
        require(d2AmountNativeValue <= poolBalance, "DSRv2_05");
        _transfer(msg.sender, address(this), d2Amount);
        if (msg.sender == address(d2Helper)) {
            payable(msg.sender).transfer(d2AmountNativeValue);
        } else {
            uint256 comission = _calculateComissionOverAmount(d2AmountNativeValue);
            payable(msg.sender).transfer(d2AmountNativeValue - comission);
            d2Helper.kickBack{ value: comission }();
        }
        _updatePoolBalance();
        return success;
    }

    /**
     * @dev Performs flash mint of D2 tokens for msg.sender address, limited to the _totalSupply amount
     * @notice The user must implement his logic inside the doSomething() function. The fee for flash mint must be paid in native tokens by calling and passing the value for the payFlashMintFee() function from the doSomething() function
     * @param d2AmountToBorrow The amount of D2 tokens the user wants to borrow
     * @param data Arbitrary data the user wants to pass to its doSomething() function
     *
     */
    function flashMint(uint256 d2AmountToBorrow, bytes calldata data) external nonReentrant performFlashMint {
        require(d2AmountToBorrow <= _totalSupply, "DSRv2_10");
        uint256 earnedBefore = totalEarnedFromFlashMintFee;
        _currentFlashMintFee = _queryNativeAmount(d2AmountToBorrow).mulDiv(FLASH_MINT_FEE, 10_000);
        _mint(msg.sender, d2AmountToBorrow);
        // Here the borrower should perform some action with the borrowed D2 amount
        ID2FlashMintBorrower(msg.sender).doSomething(d2AmountToBorrow, _currentFlashMintFee, data);
        require((totalEarnedFromFlashMintFee - earnedBefore) >= _currentFlashMintFee, "DSRv2_11");
        require(_isFlashMintPaid, "DSRv2_12");
        _burn(msg.sender, d2AmountToBorrow);
    }

    /**
     * @dev Function called inside the doSomething() function to pay fees for the flash minted amount
     *
     */
    function payFlashMintFee() external payable {
        require(_isFlashMintStarted, "DSRv2_09");
        require(msg.value >= _currentFlashMintFee, "DSRv2_11");
        totalEarned += msg.value;
        totalEarnedFromFlashMintFee += msg.value;
        toBeShared += msg.value;
        _updatePoolBalance();
        _isFlashMintPaid = true;
    }

    /**
     * @dev Needed when owner wishes to destruct the contract. For deployment with CREATE2 opcode and SALT functions only
     *
     */
    function destroy() external onlyOwner {
        selfdestruct(payable(msg.sender));
    }
}

