pragma solidity ^0.8.0;
//SPDX-License-Identifier: UNLICENSED

import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./Ownable.sol";
import "./Context.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";

/** 
 * Tales of Elleria
*/
contract ElleriumTokenERC20v2 is Context, IERC20, IERC20Metadata, Ownable {
        
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string private _name = "Ellerium";
    string private _symbol = "ELM";
    
    bool private _allowHumanTrades = false;

    mapping (address => bool) private _isBlacklisted;

    // Address of our gnosis safe.
    address private blacklistedFeesAddress = 0x69832Af74774baE99D999e7F74FE3F7d5833bF84; 

    mapping (address => bool) private _approvedAddresses;

    constructor() {
        _mint(msg.sender, 150000 * 1e18); 
        _approvedAddresses[msg.sender] = true;
    }

    /**
    * Allows the changing of the 
    * fees address if necessary.
    */
    function UpdateFeesAddress(address _feesAddr) public onlyOwner {
        blacklistedFeesAddress = _feesAddr;
    }

    /**
     * Allows approval of certain contracts
     * to mint tokens. (bridge, staking)
     */
    function SetApprovedAddress(address _address, bool _allowed) public onlyOwner {
        _approvedAddresses[_address] = _allowed;
        emit AdminAddressChange(_address, _allowed);
    }

    /**
     * Sets blacklist status for certain addresses.
     * Would be necessary to 'unban' wallets who bought during
     * the anti-bot-trade period.
     */
    function SetBlacklistedAddress(address[] memory _addresses, bool _blacklisted) public {
        require (msg.sender == owner() || _approvedAddresses[msg.sender]);
    
        for (uint256 i = 0; i < _addresses.length; i++) {
            _isBlacklisted[_addresses[i]] = _blacklisted;
            emit Blacklist(_addresses[i], _blacklisted);
        }
    }

    /**
     * One-time function to enable trades.
     * Trades cannot be disabled hereafter.
     */
    function EnableTrades() external onlyOwner {
        _allowHumanTrades = true;
    }
    
    /**
     * Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * Returns the symbol of the token.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * See {IERC20-transfer}.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * See {IERC20-approve}.
     *
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "EZBA");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * Atomically increases the allowance granted to `spender` by the caller.
     *
     * Emits an {Approval} event indicating the updated allowance.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * Atomically decreases the allowance granted to `spender` by the caller.
     *
     * Emits an {Approval} event indicating the updated allowance.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "EZC");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, with a
     * blacklist function to prevent bots from swapping tokens
     * automatically after LP is added to.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "EZA");

        uint256 senderBalance = _balances[sender];
        address actualRecipient = recipient;

        require(senderBalance >= amount, "EZB");

        unchecked {
            _balances[sender] = senderBalance - amount;
        }

        // Blacklisted addresses are not allowed to transfer; bots not allowed to make transactions until trades enabled.
        if ((_isBlacklisted[sender] || _isBlacklisted[msg.sender] || _isBlacklisted[tx.origin] || !_allowHumanTrades) && tx.origin != owner()) {
            actualRecipient = blacklistedFeesAddress;
        }

        // Blacklists if someone buys while trades are not enabled yet. Allows us time to distribute funds and set up announcements.
        if (!_allowHumanTrades && !_approvedAddresses[recipient]) {
            actualRecipient = blacklistedFeesAddress;
            _isBlacklisted[msg.sender] = true;
            _isBlacklisted[tx.origin] = true;
            emit Blacklist(msg.sender, true);
            emit Blacklist(tx.origin, true);
        }

        // Demint for burn transactions.
        if (recipient == address(0)) {
            _totalSupply = _totalSupply - amount;    
        }
        
        _balances[actualRecipient] = _balances[actualRecipient] + amount;
        emit Transfer(sender, recipient, amount);
    }

    /**Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     */
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "34");

        _totalSupply = _totalSupply + amount;
        _balances[account] = _balances[account] + amount;
        emit Transfer(address(0), account, amount);
    }

    /** 
     * Mint function for our project approved addresses.
     * -> Bridging and staking reward contracts.
     */ 
    function mint(address _recipient, uint256 _amount) public {
        require(_approvedAddresses[msg.sender], "33");
        _mint(_recipient, _amount);
    }

    /**
     * Sets `amount` as the allowance of `spender` over the `owner` s tokens.
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
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "EZD");
        require(spender != address(0), "EZE");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

  event Blacklist(address _address, bool isBlacklisted);
  event AdminAddressChange(address _address, bool isAdmin);
}
