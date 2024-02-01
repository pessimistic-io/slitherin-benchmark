
pragma solidity ^0.8.0;

import "./TransferHelper.sol";
import "./VestingMathLibrary.sol";
import "./FullMath.sol";

import "./EnumerableSet.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";


contract AMFIVesting is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct TokenLock {
        uint256 sharesDeposited;
        uint256 sharesWithdrawn;
        uint256 startEmission;
        uint256 cliffEndEmission;
        uint256 endEmission;
        uint256 lockID;
        address owner;
    }

    struct LockParams {
        address payable owner;
        uint256 amount;
        uint256 startEmission;
        uint256 cliffEndEmission;
        uint256 endEmission;
    }

    address public amfi;
    address public crowdSale;
    mapping(uint256 => TokenLock) public LOCKS;
    uint256 public NONCE = 0;
    uint256 public MINIMUM_DEPOSIT = 100;

    uint256[] private TOKEN_LOCKS;
    mapping(address => uint256[]) private USERS;

    uint public SHARES;

    event onLock(uint256 lockID, address amfiToken, address indexed owner, uint256 amountInTokens, uint256 startEmission, uint256 cliffEndEmission, uint256 endEmission);
    event onWithdraw(address indexed owner, address amfiToken, uint256 amountInTokens);
    event onTransferLock(uint256 lockIDFrom, uint256 lockIDto, address oldOwner, address newOwner);
    event CrowdSaleUpdated(address crowdSale);
    event AMFITokenUpdated(address amfiToken);


    modifier onlyCrowdSaleOrOwner() {
        require(owner() == _msgSender() || crowdSale == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    constructor(address _amfi, address _crowdSale) {
        amfi = _amfi;
        crowdSale = _crowdSale;
    }

    function updateCrowdSaleAddress(address _crowdSale) external onlyOwner {
        crowdSale = _crowdSale;

        emit CrowdSaleUpdated(_crowdSale);
    }

    function updateAMFIAddress(address _amfi) external onlyOwner {
        amfi = _amfi;

        emit AMFITokenUpdated(_amfi);
    }

    function lockCrowdsale (address owner, uint256 amount, uint256 startEmission, uint256 cliffEndEmission, uint256 endEmission) external onlyCrowdSaleOrOwner nonReentrant {
        uint256 totalAmount = amount;

        uint256 balanceBefore = IERC20(amfi).balanceOf(address(this));
        TransferHelper.safeTransferFrom(amfi, address(msg.sender), address(this), totalAmount);
        uint256 amountIn = IERC20(amfi).balanceOf(address(this)) - balanceBefore;

        uint256 shares = 0;
        require(startEmission < endEmission, 'PERIOD');
        require(startEmission < cliffEndEmission, 'CLIFF PERIOD');
        require(cliffEndEmission < endEmission, 'VESTING PERIOD');
        require(endEmission < 1e10, 'TIMESTAMP INVALID'); // prevents errors when timestamp entered in milliseconds
        require(amount >= MINIMUM_DEPOSIT, 'MIN DEPOSIT');
        uint256 amountInTokens = FullMath.mulDiv(amount, amountIn, totalAmount);

        if (SHARES == 0) {
            shares = amountInTokens;
        } else {
            shares = FullMath.mulDiv(amountInTokens, SHARES, balanceBefore == 0 ? 1 : balanceBefore);
        }
        require(shares > 0, 'SHARES');
        SHARES += shares;
        balanceBefore += amountInTokens;

        TokenLock memory token_lock;
        token_lock.sharesDeposited = shares;
        token_lock.startEmission = startEmission;
        token_lock.cliffEndEmission = cliffEndEmission;
        token_lock.endEmission = endEmission;
        token_lock.lockID = NONCE;
        token_lock.owner = owner;

        // record the lock globally
        LOCKS[NONCE] = token_lock;
        TOKEN_LOCKS.push(NONCE);

        // record the lock for the user
        uint256[] storage user = USERS[owner];
        user.push(NONCE);

        NONCE ++;
        emit onLock(token_lock.lockID, amfi, token_lock.owner, amountInTokens, token_lock.startEmission, token_lock.cliffEndEmission, token_lock.endEmission);
    }

    function lock (LockParams[] calldata _lock_params) external onlyCrowdSaleOrOwner nonReentrant {
        require(_lock_params.length > 0, 'NO PARAMS');

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _lock_params.length; i++) {
            totalAmount += _lock_params[i].amount;
        }

        uint256 balanceBefore = IERC20(amfi).balanceOf(address(this));
        TransferHelper.safeTransferFrom(amfi, address(msg.sender), address(this), totalAmount);
        uint256 amountIn = IERC20(amfi).balanceOf(address(this)) - balanceBefore;

        uint256 shares = 0;
        for (uint256 i = 0; i < _lock_params.length; i++) {
            LockParams memory lock_param = _lock_params[i];
            require(lock_param.startEmission < lock_param.endEmission, 'PERIOD');
            require(lock_param.startEmission < lock_param.cliffEndEmission, 'CLIFF PERIOD');
            require(lock_param.cliffEndEmission < lock_param.endEmission, 'VESTING PERIOD');
            require(lock_param.endEmission < 1e10, 'TIMESTAMP INVALID'); // prevents errors when timestamp entered in milliseconds
            require(lock_param.amount >= MINIMUM_DEPOSIT, 'MIN DEPOSIT');
            uint256 amountInTokens = FullMath.mulDiv(lock_param.amount, amountIn, totalAmount);

            if (SHARES == 0) {
                shares = amountInTokens;
            } else {
                shares = FullMath.mulDiv(amountInTokens, SHARES, balanceBefore == 0 ? 1 : balanceBefore);
            }
            require(shares > 0, 'SHARES');
            SHARES += shares;
            balanceBefore += amountInTokens;

            TokenLock memory token_lock;
            token_lock.sharesDeposited = shares;
            token_lock.startEmission = lock_param.startEmission;
            token_lock.cliffEndEmission = lock_param.cliffEndEmission;
            token_lock.endEmission = lock_param.endEmission;
            token_lock.lockID = NONCE;
            token_lock.owner = lock_param.owner;

            // record the lock globally
            LOCKS[NONCE] = token_lock;
            TOKEN_LOCKS.push(NONCE);

            // record the lock for the user
            uint256[] storage user = USERS[lock_param.owner];
            user.push(NONCE);

            NONCE ++;
            emit onLock(token_lock.lockID, amfi, token_lock.owner, amountInTokens, token_lock.startEmission, token_lock.cliffEndEmission, token_lock.endEmission);
        }
    }

    function withdraw (uint256 _lockID, uint256 _amount) external nonReentrant {
        TokenLock storage userLock = LOCKS[_lockID];
        require(userLock.owner == msg.sender, 'OWNER');
        // convert _amount to its representation in shares
        uint256 balance = IERC20(amfi).balanceOf(address(this));
        uint256 shareDebit = FullMath.mulDiv(SHARES, _amount, balance);
        // round _amount up to the nearest whole share if the amount of tokens specified does not translate to
        // at least 1 share.
        if (shareDebit == 0 && _amount > 0) {
            shareDebit ++;
        }
        require(shareDebit > 0, 'ZERO WITHDRAWAL');
        uint256 withdrawableShares = getWithdrawableShares(userLock.lockID);
        // dust clearance block, as mulDiv rounds down leaving one share stuck, clear all shares for dust amounts
        if (shareDebit + 1 == withdrawableShares) {
            if (FullMath.mulDiv(SHARES, balance / SHARES, balance) == 0){
                shareDebit++;
            }
        }
        require(withdrawableShares >= shareDebit, 'AMOUNT');
        userLock.sharesWithdrawn += shareDebit;

        // now convert shares to the actual _amount it represents, this may differ slightly from the
        // _amount supplied in this methods arguments.
        uint256 amountInTokens = FullMath.mulDiv(shareDebit, balance, SHARES);
        SHARES -= shareDebit;

        TransferHelper.safeTransfer(amfi, msg.sender, amountInTokens);
        emit onWithdraw(msg.sender, amfi, amountInTokens);
    }

    function transferLockOwnership (uint256 _lockID, address payable _newOwner) external onlyOwner nonReentrant {
        require(msg.sender != _newOwner, 'SELF');
        TokenLock storage transferredLock = LOCKS[_lockID];

        TokenLock memory token_lock;
        token_lock.sharesDeposited = transferredLock.sharesDeposited;
        token_lock.sharesWithdrawn = transferredLock.sharesWithdrawn;
        token_lock.startEmission = transferredLock.startEmission;
        token_lock.cliffEndEmission = transferredLock.cliffEndEmission;
        token_lock.endEmission = transferredLock.endEmission;
        token_lock.lockID = NONCE;
        token_lock.owner = _newOwner;

        // record the lock globally
        LOCKS[NONCE] = token_lock;
        TOKEN_LOCKS.push(NONCE);

        // record the lock for the new owner
        uint256[] storage newOwner = USERS[_newOwner];
        newOwner.push(token_lock.lockID);
        NONCE ++;

        // zero the lock from the old owner
        transferredLock.sharesWithdrawn = transferredLock.sharesDeposited;
        emit onTransferLock(_lockID, token_lock.lockID, msg.sender, _newOwner);
    }

    function getWithdrawableShares (uint256 _lockID) public view returns (uint256) {
        TokenLock storage userLock = LOCKS[_lockID];
        uint256 amount = userLock.sharesDeposited;
        uint256 withdrawable;
        withdrawable = VestingMathLibrary.getWithdrawableAmount (
            userLock.startEmission,
            userLock.cliffEndEmission,
            userLock.endEmission,
            amount,
            block.timestamp
        );
        if (withdrawable > 0) {
            withdrawable -= userLock.sharesWithdrawn;
        }
        return withdrawable;
    }

    function getWithdrawableTokens (uint256 _lockID) external view returns (uint256) {
        TokenLock storage userLock = LOCKS[_lockID];
        uint256 withdrawableShares = getWithdrawableShares(userLock.lockID);
        uint256 balance = IERC20(amfi).balanceOf(address(this));
        uint256 amountTokens = FullMath.mulDiv(withdrawableShares, balance, SHARES == 0 ? 1 : SHARES);
        return amountTokens;
    }

    // For UI use
    function convertSharesToTokens (uint256 _shares) external view returns (uint256) {
        uint256 balance = IERC20(amfi).balanceOf(address(this));
        return FullMath.mulDiv(_shares, balance, SHARES);
    }

    function convertTokensToShares (uint256 _tokens) external view returns (uint256) {
        uint256 balance = IERC20(amfi).balanceOf(address(this));
        return FullMath.mulDiv(SHARES, _tokens, balance);
    }

    function getLock (uint256 _lockID) external view returns (uint256, address, uint256, uint256, uint256, uint256, uint256, uint256, uint256, address) {
        TokenLock memory tokenLock = LOCKS[_lockID];

        uint256 balance = IERC20(amfi).balanceOf(address(this));
        uint256 totalSharesOr1 = SHARES == 0 ? 1 : SHARES;
        // tokens deposited and tokens withdrawn is provided for convenience in UI, with rebasing these amounts will change
        uint256 tokensDeposited = FullMath.mulDiv(tokenLock.sharesDeposited, balance, totalSharesOr1);
        uint256 tokensWithdrawn = FullMath.mulDiv(tokenLock.sharesWithdrawn, balance, totalSharesOr1);
        return (tokenLock.lockID, amfi, tokensDeposited, tokensWithdrawn, tokenLock.sharesDeposited, tokenLock.sharesWithdrawn, tokenLock.startEmission, tokenLock.cliffEndEmission, tokenLock.endEmission,
        tokenLock.owner);
    }

    function getTokenLocksLength () external view returns (uint256) {
        return TOKEN_LOCKS.length;
    }

    function getTokenLockIDAtIndex (uint256 _index) external view returns (uint256) {
        return TOKEN_LOCKS[_index];
    }

    function getUserLocksLength (address _user) external view returns (uint256) {
        return USERS[_user].length;
    }

    function getUserLockIDAtIndex (address _user, uint256 _index) external view returns (uint256) {
        return USERS[_user][_index];
    }
}

