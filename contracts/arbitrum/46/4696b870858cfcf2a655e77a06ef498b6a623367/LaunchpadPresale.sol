import "./ReentrancyGuard.sol";
import "./Context.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./Address.sol";

// File: @openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol


// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/draft-IERC20Permit.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 */
interface IERC20Permit {
    /**
     * @dev Sets `value` as the allowance of `spender` over ``owner``'s tokens,
     * given ``owner``'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// File: @openzeppelin/contracts/token/ERC20/IERC20.sol


// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

// File: @openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol


// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.0;




/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    function safePermit(
        IERC20Permit token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        uint256 nonceBefore = token.nonces(owner);
        token.permit(owner, spender, value, deadline, v, r, s);
        uint256 nonceAfter = token.nonces(owner);
        require(nonceAfter == nonceBefore + 1, "SafeERC20: permit did not succeed");
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

pragma solidity ^0.8.0;


interface IERC20Extended is IERC20 {
    function decimals() external  view returns (uint8);
}

pragma solidity ^0.8.0;

// Have fun reading it. Hopefully it's bug-free. 
contract LaunchpadPresale is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20Extended;

    // Info of each user.
    struct UserInfo {
        uint256 amountPrivate; // How many LP tokens the user has provided.
        uint256 amountPublic; // How many LP tokens the user has provided.
        uint256 pendingTotalTokensPrivate; // pendingTotalTokens
        uint256 pendingTotalTokensPublic; // pendingTotalTokens
        bool claimed;
    }

    /****** Sale Status ******/
    bool public whitelistEnabled = true;
    bool public configEnabled = true;
    bool public publicEnabled = false;
    uint256 public presaleStart = block.timestamp + 30 days;
    uint256 public presaleEnd = block.timestamp + 32 days;

    /****** Token Details ******/
    IERC20Extended public TKN;
    IERC20Extended public TKN2;
    IERC20Extended public raisedTKN;
    address public wethAddressDefault = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    /****** Sale Raise Details ******/
    uint256 public TKNPerRaisedTKN; // X TKN = 1 raisedTKN
    uint256 public totalRaised; // total raised so far
    uint256 public presaleHardcap; // sale hardcap
    uint256 public remainingTokensAvailable; // remaining tokens to be sold until hardcap
    uint256 public privatePresaleThreshold; // private presale hardcap (lower than hardcap)

    uint256 public minCapUserPrivate; // min cap user private
    uint256 public maxCapUserPrivate; // max cap user private
    uint256 public minCapUserPublic; // min cap user public
    uint256 public maxCapUserPublic; // max cap user public

    uint256 public token1RatioPrivate; // 100 = 10%
    uint256 public token1RatioPublic;
    
    /****** Dev Details ******/
    address public fundsReceiver;
    
    
    mapping (address => UserInfo) public userInfo;
    mapping (address => bool) public whitelist;

    event Deposit(uint256 amount);
    event claimTKNtoken(uint256 _amount, uint256 _amount2);

    constructor(
        IERC20Extended _TKN,
        IERC20Extended _TKN2,
        IERC20Extended _raisedTKN,
        address _fundsReceiver,
        uint256 _privatePresaleThreshold,
        uint256 _presaleHardcap,
        uint256 _TKNPerRaisedTKN,
        uint256[] memory _presaleCaps,
        uint256 _token1RatioPrivate,
        uint256 _token1RatioPublic
    ) {
        TKN = _TKN;
        TKN2 = _TKN2;
        raisedTKN = _raisedTKN;
        fundsReceiver = _fundsReceiver;
        presaleHardcap = _presaleHardcap;
        remainingTokensAvailable =_presaleHardcap;
        privatePresaleThreshold = _privatePresaleThreshold;
        TKNPerRaisedTKN = _TKNPerRaisedTKN; // 1 PRISM = 50$ -> 38000000000000000000 -> 38 PRISM = 1 ETH (1 PRISM = 0.0263 ETH)
        minCapUserPrivate = _presaleCaps[0];
        maxCapUserPrivate = _presaleCaps[1];
        minCapUserPublic = _presaleCaps[2];
        maxCapUserPublic = _presaleCaps[3];
        token1RatioPrivate = _token1RatioPrivate;
        token1RatioPublic = _token1RatioPublic;
    }

    // Get into presale
    function deposit() public payable nonReentrant {
        require(block.timestamp >= presaleStart, "not opened");
        require(block.timestamp <= presaleEnd, "presale ended");
        require(address(raisedTKN) == wethAddressDefault, "Can't use ETH to buy this presale");
        require(msg.value <= remainingTokensAvailable, "not enough allocation");

        UserInfo storage user = userInfo[msg.sender];

        if (!publicEnabled) { // private phase
            if (whitelistEnabled) {
                require(whitelist[msg.sender], "not in whitelist");
            }
            require(msg.value >= getMinAllocation(), "cant buy this little");
            require((user.amountPrivate+msg.value) <= getMaxAllocation(), "max allocation reached");
            user.amountPrivate = user.amountPrivate.add(msg.value);
            user.pendingTotalTokensPrivate = user.amountPrivate.mul(TKNPerRaisedTKN).div(10**raisedTKN.decimals());
            totalRaised = totalRaised.add(msg.value);
            remainingTokensAvailable = remainingTokensAvailable.sub(msg.value);
            if (totalRaised > privatePresaleThreshold){
                updateSalePhase();
            }
            // payable(fundsReceiver).transfer(msg.value);

            (bool sent, ) = payable(fundsReceiver).call{gas: 25000, value: msg.value}(""); //set max gas limit as 25000 gas
            require(sent, "failure to send ether");
        } else { // public phase
            require(msg.value >= getMinAllocation(), "cant buy this little");
            require((user.amountPublic+msg.value) <= getMaxAllocation(), "max allocation reached");
            user.amountPublic = user.amountPublic.add(msg.value);
            user.pendingTotalTokensPublic = user.amountPublic.mul(TKNPerRaisedTKN).div(10**raisedTKN.decimals());
            totalRaised = totalRaised.add(msg.value);
            remainingTokensAvailable = remainingTokensAvailable.sub(msg.value);

            // payable(fundsReceiver).transfer(msg.value);

            (bool sent, ) = payable(fundsReceiver).call{gas: 25000, value: msg.value}(""); //set max gas limit as 25000 gas
            require(sent, "failure to send ether");
        }

        emit Deposit(msg.value);
    }

    // Get into presale
    function depositGeneral(uint256 _amount) public nonReentrant {
        require(block.timestamp >= presaleStart, "not opened");
        require(block.timestamp <= presaleEnd, "presale ended");
        require(_amount <= remainingTokensAvailable, "not enough allocation");
        UserInfo storage user = userInfo[msg.sender];

        if (!publicEnabled) { // private phase
            if (whitelistEnabled) {
                require(whitelist[msg.sender], "not in whitelist");
            }
            require(_amount >= getMinAllocation(), "cant buy this little");
            require((user.amountPrivate+_amount) <= getMaxAllocation(), "max allocation reached");
            user.amountPrivate = user.amountPrivate.add(_amount);
            user.pendingTotalTokensPrivate = user.amountPrivate.mul(TKNPerRaisedTKN).div(10**raisedTKN.decimals());
            totalRaised = totalRaised.add(_amount);
            remainingTokensAvailable = remainingTokensAvailable.sub(_amount);
            if (totalRaised > privatePresaleThreshold){
                updateSalePhase();
            }
            raisedTKN.safeTransferFrom(address(msg.sender), fundsReceiver, _amount);
        } else { // public phase
            require(_amount >= getMinAllocation(), "cant buy this little");
            require((user.amountPublic+_amount) <= getMaxAllocation(), "max allocation reached");
            user.amountPublic = user.amountPublic.add(_amount);
            user.pendingTotalTokensPublic = user.amountPublic.mul(TKNPerRaisedTKN).div(10**raisedTKN.decimals());
            totalRaised = totalRaised.add(_amount);
            remainingTokensAvailable = remainingTokensAvailable.sub(_amount);

            raisedTKN.safeTransferFrom(address(msg.sender), fundsReceiver, _amount);
        }

        emit Deposit(_amount);
    }

    // Claim tokens after presale ends
    function claimTKN() external nonReentrant {  
        require(block.timestamp >= presaleEnd + 3600, "not claimable yet");
        UserInfo storage user = userInfo[msg.sender];
        require(user.claimed == false, "claimed");
        uint256 amountPrivate = user.pendingTotalTokensPrivate;
        uint256 amountPublic = user.pendingTotalTokensPublic;
        uint256 TKNamount = (amountPrivate.mul(token1RatioPrivate).div(1000)).add(amountPublic.mul(token1RatioPublic).div(1000));
        uint256 TKN2amount = amountPrivate.add(amountPublic).sub(TKNamount);
        user.claimed = true;
        safeTKNTransfer(msg.sender, TKNamount);
        safeTKN2Transfer(msg.sender, TKN2amount);
        emit claimTKNtoken(TKNamount, TKN2amount);
    }

    /* ==================================== ==================================== */
    /* ==================================== ==================================== */
    /* ==================================== INTERNAL ==================================== */

    // View function to see pending TKNs on frontend.
    function updateTKNperRaisedTKN() internal {
        TKNPerRaisedTKN = 27150000000000000000; // 70$ = 27150000000000000000 (27,15 PRISM = 1 ETH) (1 PRISM = 0.037 ETH)
    }

    // Update presale phase to public when privateSaleThreshold is met
    function updateSalePhase() internal {
        publicEnabled = true;
        updateTKNperRaisedTKN();
    }


    // Safe TKN transfer function, just in case if rounding error causes pool to not have enough TKNs.
    function safeTKNTransfer(address _to, uint256 _amount) internal {
        uint256 TKNBal = TKN.balanceOf(address(this));
        if (_amount > TKNBal) {
            TKN.transfer(_to, TKNBal);
        } else {
            TKN.transfer(_to, _amount);
        }
    }

    function safeTKN2Transfer(address _to, uint256 _amount) internal {
        uint256 TKN2Bal = TKN2.balanceOf(address(this));
        if (_amount > TKN2Bal) {
            TKN2.transfer(_to, TKN2Bal);
        } else {
            TKN2.transfer(_to, _amount);
        }
    }

    /* ==================================== UTILITY ==================================== */

    // View function to see pending TKNs on frontend.
    function getPendingTKN(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 TKNamount = (user.pendingTotalTokensPrivate).add(user.pendingTotalTokensPublic);
        return TKNamount;
    }
    function getRemainingAllocationUser(address _user)public view returns(uint256){
        UserInfo storage user = userInfo[_user];
        return publicEnabled ? getMaxAllocation().sub(user.amountPublic) : getMaxAllocation().sub(user.amountPrivate);
    }

    function getMaxAllocation() public view returns(uint256){
        return publicEnabled ? maxCapUserPublic : maxCapUserPrivate;
    }

    function getMinAllocation() public view returns(uint256){
        return publicEnabled ? minCapUserPublic : minCapUserPrivate;
    }

    /* ==================================== DEV CONTROLS ==================================== */

    // Update fundsReceiver address by the previous fundsReceiver.
    function setFundsReceiver(address _fundsReceiver) public {
        require(msg.sender == fundsReceiver, "fundsReceiver: wut?");
        fundsReceiver = _fundsReceiver;
    }

    function setPublicEnabledStatus(bool _status) external onlyOwner {
        publicEnabled = _status;
    }

    function setTokenRatios(uint256 _token1RatioPrivate, uint256 _token1RatioPublic) external onlyOwner {
        require(configEnabled, "Config is disabled");
        token1RatioPrivate = _token1RatioPrivate;
        token1RatioPublic = _token1RatioPublic;
    }

    function setPresaleTimes(uint256 _presaleStart, uint256 _presaleEnd) external onlyOwner {
        require(configEnabled, "Config is disabled");
        presaleStart = _presaleStart;
        presaleEnd = _presaleEnd;
    }

    function setPresaleHardcap(uint256 _privatePresaleThreshold, uint256 _presaleHardcap) external onlyOwner {
        require(configEnabled, "Config is disabled");
        privatePresaleThreshold = _privatePresaleThreshold;
        presaleHardcap = _presaleHardcap;
    }

    // Disable config methods
    function disableConfig() external onlyOwner {
        require(configEnabled, "Config is disabled");
        configEnabled = false;
    }

    function getUnsoldTokens(address _to, uint256 _amount, uint256 _tokenType) external onlyOwner {
        require(block.timestamp > presaleEnd + 14 days);
        if (_tokenType == 0) {
            safeTKNTransfer(_to, _amount);
        } else {
            safeTKN2Transfer(_to, _amount);
        }
    }

    function closePrivatePresaleUpdatePrices() external onlyOwner {
        publicEnabled = true;
        updateTKNperRaisedTKN();
    }

    function closePrivatePresaleOnly() external onlyOwner {
        publicEnabled = true;
    }

    /* ==================================== WHITELIST ==================================== */

    function setWhitelistEnabled(bool _status) external onlyOwner {
        whitelistEnabled = _status;
    }

    function setWhitelist(address[] memory _wallets, bool _whitelisted) external onlyOwner {
        require(configEnabled, "Config is disabled");
        for (uint256 i = 0; i < _wallets.length; i++) {
            whitelist[_wallets[i]] = _whitelisted;
        }
    }
}
