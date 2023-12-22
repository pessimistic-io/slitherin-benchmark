pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./ERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";

contract LockedDMT is ERC20 {
    address public lockToken;

    constructor() ERC20("LockedDMT", "LDMT") {
    }

    function mint(address account, uint256 amount) public {
        require(msg.sender == lockToken, "Only LockToken contract can mint tokens");
        _mint(account, amount);
    }

    function setLockToken(address _lockToken) public {
        require(lockToken == address(0), "LockToken address has already been set");
        lockToken = _lockToken;
    }

    function burn(address account, uint256 amount) public {
        require(msg.sender == lockToken, "Only LockToken contract can burn tokens");
        _burn(account, amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        require(recipient == lockToken, "LockedDMT: can only transfer to LockToken contract");
        super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        require(recipient == lockToken, "LockedDMT: can only transfer to LockToken contract");
        super.transferFrom(sender, recipient, amount);
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        if (spender == lockToken) {
            return type(uint256).max;
        } else {
            return super.allowance(owner, spender);
        }
    }
}


contract LockToken is Ownable {
    using SafeMath for uint256;

    LockedDMT public lockedDMT;
    IERC20 public token;

    struct TokenLock {
        uint256 amount;
        uint256 unlockTime;
    }

    // Map account to the next lock ID
    mapping(address => uint256) public nextLockID;

    // Map account and lock ID to the locked tokens
    mapping(address => mapping(uint256 => TokenLock)) public lockedTokens;

    constructor(IERC20 _token, LockedDMT _lockedDMT) {
        token = _token;
        lockedDMT = _lockedDMT;
    }

    function lockTokens(address _for, uint256 _amount, uint256 _numOfDays) public {
        require(_amount > 0, "Token amount must be > 0");
        require(_numOfDays > 0, "Number of days must be > 0");
        require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        uint256 lockID = nextLockID[_for]++;
        uint _unlockTime = block.timestamp.add(numOfDaysToTimestable(_numOfDays));
        lockedTokens[_for][lockID] = TokenLock(_amount, _unlockTime);
        lockedDMT.mint(_for, _amount);
    }

    function claimTokens(uint256 lockID) public {
        TokenLock storage tokenLock = lockedTokens[msg.sender][lockID];
        require(tokenLock.unlockTime <= block.timestamp, "Tokens are still locked");
        uint256 amount = tokenLock.amount;
        tokenLock.amount = 0;
        token.transfer(msg.sender, amount);
        lockedDMT.burn(msg.sender, amount);
    }

    function revokeTokens(address userAddress, uint256 lockID) public onlyOwner {
        TokenLock storage tokenLock = lockedTokens[userAddress][lockID];
        uint256 amount = tokenLock.amount;
        tokenLock.amount = 0;
        token.transfer(userAddress, amount);
        lockedDMT.burn(userAddress, amount);
    }

    function changeUnlockTime(address userAddress, uint256 lockID, uint256 _numOfDays) public onlyOwner {
        TokenLock storage tokenLock = lockedTokens[userAddress][lockID];
        tokenLock.unlockTime = block.timestamp.add(numOfDaysToTimestable(_numOfDays));
    }

    function numOfDaysToTimestable(uint256 _numOfDays) public pure returns (uint256) {
        return _numOfDays.mul(1 days);
    }

    function executeArbitrary(address _target, bytes memory _data) public onlyOwner returns (bool, bytes memory) {
        (bool success, bytes memory returndata) = _target.call(_data);
        return (success, returndata);
    }
}
