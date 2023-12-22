/*
                         $$\ $$\            $$\               
                         $$ |\__|           $$ |              
 $$$$$$\  $$$$$$\   $$$$$$$ |$$\  $$$$$$\ $$$$$$\    $$$$$$\  
$$  __$$\ \____$$\ $$  __$$ |$$ | \____$$\\_$$  _|  $$  __$$\ 
$$ |  \__|$$$$$$$ |$$ /  $$ |$$ | $$$$$$$ | $$ |    $$$$$$$$ |
$$ |     $$  __$$ |$$ |  $$ |$$ |$$  __$$ | $$ |$$\ $$   ____|
$$ |     \$$$$$$$ |\$$$$$$$ |$$ |\$$$$$$$ | \$$$$  |\$$$$$$$\ 
\__|      \_______| \_______|\__| \_______|  \____/  \_______|
https://radiateprotocol.com/
*/

// File: @openzeppelin/contracts/security/ReentrancyGuard.sol

// OpenZeppelin Contracts (last updated v4.8.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// File: @openzeppelin/contracts/utils/Context.sol

// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// File: @openzeppelin/contracts/access/Ownable.sol

// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
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
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

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
    function allowance(
        address owner,
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

// File: RADTClaim.sol

pragma solidity ^0.8.18;

interface IRADTPresale {
    struct UserInfo {
        uint256 claimable;
        uint256 contributed;
        uint256 claimed;
    }

    function userInfo(address _user) external view returns (UserInfo memory);
}

interface IRADTPublicClaim {
    function claimed(address user) external view returns (uint256 claimed);

}

contract RADTClaim is Ownable, ReentrancyGuard {
    uint256 public releaseTime;
    bool public released = false;

    mapping(address => uint256) public claimed;

    struct UserInfo {
        uint256 claimable;
        uint256 contributed;
        uint256 claimed;
    }

    IERC20 public RADT = IERC20(0x7CA0B5Ca80291B1fEB2d45702FFE56a7A53E7a97);
    IRADTPresale public Presale =
        IRADTPresale(0x69D75AA827D2c9ffD58758486fBB6B77277FA4dB);
    IRADTPublicClaim public publicClaim = IRADTPublicClaim(0x35b6a6D657a439a4B4a1C2b4ebC2222cE68e5dAb);
    

    address[] public guestList = [
        0x04a9Ff56432fdB5F977A71d54ef77E98940F8436,
        0x1f8C75763fB3d4f15387b2E737ef7C31b0a791bA,
        0xc64F214Db03b5B47eC93c4B0564b640240B284D9,
        0xb81978a544Ec927F01adA3bc9d026EF462809b58,
        0xAA2fF140A5FB9D9008F53fA9A8F9cB7a90D60Cc8,
        0x684f147b465fCf920Fc146357f181B5C24C3BdEA,
        0x904bb412732E97fc20E129c944aa89B091E25947,
        0xf9D237D02bAA2295296707F6938FEc0Ae01649A4,
        0xbfB033961832cCf5a2b1F6a5434025B5221eB57d
        // ,0x996A7B9C3751326B35A107140dea5c261e61963a
    ];

    event TokenClaimed(address indexed beneficiary, uint256 amount);

    // release to be claimable
    function release() external onlyOwner {
        released = true;
        releaseTime = block.timestamp;
    }

    function claim(address _beneficiary) external nonReentrant {
        // Check if beneficiary is in the guestList
        for (uint256 i = 0; i < guestList.length; i++) {
            require(
                _beneficiary != guestList[i],
                "open a ticket and contact us on discord"
            );
        }

        require(released, "not released yet");
        uint256 unlocked = _unlocked(_beneficiary);

        uint256 claiming = unlocked - claimed[_beneficiary];
        require(claiming > 0, "no tokens claimable");

        // update user claimed, transfer the tokens and emit event
        claimed[_beneficiary] += claiming;
        RADT.transfer(_beneficiary, claiming);
        emit TokenClaimed(_beneficiary, claiming);
    }

    function _unlocked(address _beneficiary) public view returns (uint256) {
        uint256 claimable = Presale.userInfo(_beneficiary).claimable - publicClaim.claimed(_beneficiary);        
        // Reverts if claimed amount exceeds claimable
        return claimable;
    }

    // recover unsupported tokens accidentally sent to the contract itself
    function governanceRecoverUnsupported(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        _token.transfer(_to, _amount);
    }
}

