// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IMintable.sol";
import "./EnumerableSet.sol";

interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the token decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the token symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the token name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(
        address _owner,
        address spender
    ) external view returns (uint256);

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
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

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
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     */
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     */
    function _transferOwnership(address newOwner) internal {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract ESSBaseToken is Context, Ownable, IMintable, IERC20 {
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;
    mapping(address => bool) private minterMap;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    uint8 private _decimals;
    string private _symbol;
    string private _name;
    bool public isInitialized = false;

    function init() internal {
       _name = "Escrowed LionDEX Token";
       _symbol = "esLION";
       _decimals = 18;
    }

    modifier onlyMinter() {
        require(isMinter(msg.sender), "caller is not the Minter");
        _;
    }

    function setMinter(address addr) public onlyOwner {
        minterMap[addr] = true;
    }

    function removeMinter(address addr) public onlyOwner {
        minterMap[addr] = false;
    }

    function isMinter(address addr) public view returns (bool) {
        return minterMap[addr];
    }

    /**
     * @dev Returns the token decimals.
     */
    function decimals() external view returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Returns the token symbol.
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the token name.
     */
    function name() external view returns (string memory) {
        return _name;
    }

    /**
     * @dev See {ERC20-totalSupply}.
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {ERC20-balanceOf}.
     */
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {ERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {ERC20-allowance}.
     */
    function allowance(
        address owner,
        address spender
    ) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {ERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    // function approve(address spender) external returns (bool) {
    //     _approve(_msgSender(), spender, uint256(type(uint256).max));
    //     return true;
    // }

    /**
     * @dev See {ERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20};
     *
     * Requirements:
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for `sender`'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {ERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {ERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    /**
     * @dev Creates `amount` tokens and assigns them to `msg.sender`, increasing
     * the total supply.
     *
     * Requirements
     *
     * - `msg.sender` must be the token minter
     */
    function mint(
        address _account,
        uint256 _amount
    ) external override onlyMinter {
        _mint(_account, _amount);
    }

    /**
     * @dev Burn `amount` tokens and decreasing the total supply.
     */
    //    function burn(address _account, uint256 _amount) external override onlyMinter {
    //        _burn(_account, _amount);
    //    }

    function burn(uint256 _amount) external {
        _burn(_msgSender(), _amount);
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _balances[sender] = _balances[sender].sub(
            amount,
            "ERC20: transfer amount exceeds balance"
        );
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        _balances[account] = _balances[account].sub(
            amount,
            "ERC20: burn amount exceeds balance"
        );
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
     *
     * This is internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

}

contract esLionTokenVester is ESSBaseToken {
    using SafeMath for uint256;
    using SafeMath for uint32;
    using EnumerableSet for EnumerableSet.UintSet;

    struct ClaimInfo {
        uint256 total;
        uint256 claimed;
        uint32 startTime;
        uint32 duration;
    }

    IERC20 public LionToken;
    uint32 public duration = 180 days;
    uint256 public currentMaxIndex; //start from 1
    uint256 public minDepositAmount = 100e18;
    //user=>deposit id
    mapping(address => EnumerableSet.UintSet) private ownerIndexes;
    //deposit id=>user's claim info
    mapping(uint256 => ClaimInfo) public indexesClaimInfo;

    event Deposit(address user, uint256 currentIndex, uint256 amount);
    event ClaimLion(address user, uint256 amount);
    event Vest(address user, uint256 amount);

    function initialize(IERC20 _LionToken) public {
        require(!isInitialized, "esLionTokenVester: inited");
        isInitialized = true;
        _transferOwnership(msg.sender);
        init();
        LionToken = _LionToken;
        duration = 180 days;
        minDepositAmount = 100e18;
    }

    function deposit(uint256 amount) public {
        require(
            amount >= minDepositAmount,
            "esLionTokenVester: amount less than min amount"
        );
        require(
            balanceOf(msg.sender) >= amount,
            "esLionTokenVester: esLion balance invalid"
        );
        require(
            allowance(msg.sender, address(this)) >= amount,
            "esLionTokenVester: esLion allowance invalid"
        );
        _burn(msg.sender, amount);
        uint256 currentIndex = ++currentMaxIndex;
        ownerIndexes[msg.sender].add(currentIndex);
        indexesClaimInfo[currentIndex] = ClaimInfo(
            amount,
            0,
            uint32(block.timestamp),
            duration
        );

        emit Deposit(msg.sender, currentIndex, amount);
    }

    //deposit lion,return eslion
    function vest(uint256 amount) public {
        require(
            LionToken.balanceOf(msg.sender) >= amount,
            "esLionTokenVester: Lion balance invalid"
        );
        require(
            LionToken.allowance(msg.sender, address(this)) >= amount,
            "esLionTokenVester: Lion allowance invalid"
        );
        LionToken.transferFrom(msg.sender, address(this), amount);
        emit Vest(msg.sender, amount);
    }

    function claimLion() public {
        uint256 len = ownerIndexes[msg.sender].length();
        uint256 total;

        for (uint i; i < len; i++) {
            uint256 index = ownerIndexes[msg.sender].at(i);
            ClaimInfo storage info = indexesClaimInfo[index];
            (, uint256 canClaim, ) = getCanClaim(index);
            info.claimed = info.claimed.add(canClaim);
            total = total.add(canClaim);
        }
        if (total > 0) {
            LionToken.transfer(msg.sender, total);
        }
        //remove index from index set if user claimed all lion
        cleanIndexForUser(msg.sender);

        emit ClaimLion(msg.sender, total);
    }

    function claimLionOfIndex(uint256 fromIndex, uint256 toIndex) public {
        require(fromIndex < toIndex, "esLionTokenVester: params invalid");

        uint256 len = ownerIndexes[msg.sender].length();
        if (toIndex > len) {
            toIndex = len;
        }
        uint256 total;

        for (uint i = fromIndex; i < toIndex; i++) {
            uint256 index = ownerIndexes[msg.sender].at(i);
            ClaimInfo storage info = indexesClaimInfo[index];
            (, uint256 canClaim, ) = getCanClaim(index);
            info.claimed = info.claimed.add(canClaim);
            total = total.add(canClaim);
        }
        if (total > 0) {
            LionToken.transfer(msg.sender, total);
        }
        //remove index from index set if user claimed all lion
        //cleanIndexForUser(msg.sender);
        cleanIndexForUserIndex(msg.sender,fromIndex,toIndex);

        emit ClaimLion(msg.sender, total);
    }

    function cleanIndexForUserIndex(
        address user,
        uint256 from,
        uint256 to
    ) public {
        require(from < to, "esLionTokenVester: param invalid");
        uint256 len = ownerIndexes[user].length();
        if (to > len) {
            to = len;
        }
        uint256[] memory needDeleteIndex = new uint256[](len);
        for (uint i = from; i < to; i++) {
            uint256 index = ownerIndexes[user].at(i);
            ClaimInfo memory info = indexesClaimInfo[index];
            if (info.total <= info.claimed) {
                needDeleteIndex[i] = index;
            }
        }
        for (uint i; i < len; i++) {
            if (needDeleteIndex[i] > 0) {
                ownerIndexes[user].remove(needDeleteIndex[i]);
            }
        }
    }

    function cleanIndexForUser(address user) public {
        uint256 len = ownerIndexes[user].length();
        uint256[] memory needDeleteIndex = new uint256[](len);
        for (uint i; i < len; i++) {
            uint256 index = ownerIndexes[user].at(i);
            ClaimInfo memory info = indexesClaimInfo[index];
            if (info.total <= info.claimed) {
                needDeleteIndex[i] = index;
            }
        }
        for (uint i; i < len; i++) {
            if (needDeleteIndex[i] > 0) {
                ownerIndexes[user].remove(needDeleteIndex[i]);
            }
        }
    }

    function getCanClaim(
        uint256 index
    ) public view returns (uint256 total, uint256 canClaim, uint256 claimed) {
        ClaimInfo memory info = indexesClaimInfo[index];
        claimed = info.claimed;
        total = info.total;
        if (block.timestamp <= info.startTime) {
            return (total, 0, 0);
        }

        if (uint32(block.timestamp) >= info.startTime.add(info.duration)) {
            canClaim = info.total.sub(claimed);
            return (total, canClaim, claimed);
        }

        canClaim = info.total.mul((block.timestamp.sub(info.startTime))).div(
            info.duration
        );
        canClaim = canClaim.sub(claimed);
    }

    function getUserClaimInfo(
        address user
    )
        external
        view
        returns (uint256 totalRet, uint256 claimedRet, uint256 canClaimRet)
    {
        for (uint i = 0; i < ownerIndexes[user].length(); i++) {
            uint256 index = ownerIndexes[user].at(i);
            (uint256 total, uint256 canClaim, uint256 claimed) = getCanClaim(
                index
            );
            totalRet = totalRet.add(total);
            claimedRet = claimedRet.add(claimed);
            canClaimRet = canClaimRet.add(canClaim);
        }
    }

    function getUserIndex(
        address user
    ) external view returns (uint256[] memory indexes) {
        uint256 len = ownerIndexes[user].length();
        indexes = new uint256[](len);
        for (uint i = 0; i < len; i++) {
            indexes[i] = ownerIndexes[user].at(i);
        }
    }

    function setToken(IERC20 _LionToken) external onlyOwner {
        LionToken = _LionToken;
    }

    function setDuration(uint32 _duration) external onlyOwner {
        duration = _duration;
    }

    function setMinDepositAmount(uint256 _minDepositAmount) external onlyOwner {
        minDepositAmount = _minDepositAmount;
    }
}

