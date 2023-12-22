// SPDX-License-Identifier: MIT


pragma solidity ^0.8.17;

interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

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
    function transfer(address recipient, uint256 amount) external returns (bool);

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

    function burn(uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;

    function feeDistribution(uint _amount, address _addr) external;

    function emission(uint256 amount) external;

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);

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
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);


}

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

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

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
        require(newOwner != address(0), "Ownable: new owner is the zero address");
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


contract STTExchange is Ownable {
    IERC20 public STT = IERC20(0x1635b6413d900D85fE45C2541342658F4E982185);
    IERC20 public USDT = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

    uint public rRate;
    uint public minUSDTEmission = 10000000;
    uint public minSTT = 1000000000;
    bool public statusAdditionEmission;

    //In bps, example 100 = 1%
    uint public fee = 100;
    //10000 = 1, 3800 = 0.38
    uint public ratio = 3800;

    function swap( uint _amountSTT) public {
        require(_amountSTT >= minSTT);
        countingRate();

        //Distribution fee
        uint _fee = calculate(_amountSTT, fee);
        STT.burnFrom(msg.sender, _amountSTT - _fee);
        STT.feeDistribution(_fee, msg.sender);

        //USDT transfer 
        uint _amountUSDT = ((_amountSTT - _fee) / 1000000000) * rRate;
        USDT.transfer(msg.sender, _amountUSDT);
    }

    function deposit(uint _amount) public {
        countingRate();

        //Cheks off/on addition emission
        if(statusAdditionEmission) {
            USDT.transferFrom(msg.sender, address(this), _amount);
            //Cheks min USDT for starting addition emission
            if(_amount >= minUSDTEmission) {
                emmisionSTT(_amount);
            }
        } else {
            USDT.transferFrom(msg.sender, address(this), _amount);
        } 
    }

    function emmisionSTT(uint _usdt) private {
        uint _amountEm = calculate(_usdt * 10 ** 9 / rRate, ratio) ;
        STT.emission(_amountEm);
    }

    function countingRate() private {
       rRate = (USDT.balanceOf(address(this)) * 10 ** 9)  / STT.totalSupply();
    }

    // Counting an percentage by basis points
    function calculate(uint256 amount, uint256 bps) public pure returns (uint256) {
        require((amount * bps) >= 10000);
        return amount * bps / 10000;
    }

    //ADMIN FUNCTIONS
    function setRatio(uint _ratio) public onlyOwner {
        ratio = _ratio;
    }

    function setFee(uint _fee) public onlyOwner {
        require(_fee <= 1500);
        fee = _fee;
    }

    function setMin(uint _minUSDTEmission, uint _minSTT) public onlyOwner {
        minUSDTEmission = _minUSDTEmission;
        minSTT = _minSTT;
    }
    
    function setStatusAdditionEmission(bool _status) public onlyOwner {
        statusAdditionEmission = _status;
    }
}