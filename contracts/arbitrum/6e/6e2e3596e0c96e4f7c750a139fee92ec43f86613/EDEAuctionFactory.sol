// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./Ownable.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";

interface IERC20Permit {

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function nonces(address owner) external view returns (uint256);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

library Address {
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }


    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success,) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                // only check isContract if the call was successful and the return data is empty
                // otherwise we already know that it was a contract
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert(errorMessage);
        }
    }
}

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

interface IExtendedERC20 is IERC20 {
    function decimals() external view returns (uint256);
}

abstract contract DutchAuction is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public admin;
    address public auctionTreasury;
    address public auctionToken;
    address public payToken;
    bool public finalized;
    uint128 public totalTokens;

    uint64 public startTime;
    uint64 public endTime;
    uint128 public startPrice;
    uint128 public minimumPrice;
    uint128 public commitmentsTotal;

    mapping(address => uint256) public commitments;
    mapping(address => uint256) public claimed;

    constructor(
        address _auctionToken,
        address _payToken,
        uint128 _totalTokens,
        uint64 _startTime,
        uint64 _endTime,
        uint128 _startPrice,
        uint128 _minimumPrice,
        address _admin,
        address _treasury
    ) {
        require(_endTime < 10000000000, "unix timestamp in seconds");
//        require(_startTime >= block.timestamp, "start time < current time");
        require(_endTime > _startTime, "end time < start price");
        require(_totalTokens != 0, "total tokens = 0");
        require(_startPrice > _minimumPrice, "start price < minimum price");
        require(_minimumPrice != 0, "minimum price = 0");
        require(_treasury != address(0), "address = 0");
        require(_admin != address(0), "address = 0");
        require(IExtendedERC20(_auctionToken).decimals() == 18, "decimals != 18");

        startTime = _startTime;
        endTime = _endTime;
        totalTokens = _totalTokens;

        startPrice = _startPrice;
        minimumPrice = _minimumPrice;

        auctionToken = _auctionToken;
        payToken = _payToken;
        auctionTreasury = _treasury;
        admin = _admin;
        emit AuctionDeployed(
            _auctionToken, _payToken, _totalTokens, _startTime, _endTime, _startPrice, _minimumPrice, _admin, _treasury
        );
    }

    function tokenPrice() public view returns (uint256) {
        return uint256(commitmentsTotal) * 1e18 / uint256(totalTokens);
    }

    function priceFunction() public view returns (uint256) {
        if (block.timestamp <= startTime) {
            return startPrice;
        }
        if (block.timestamp >= endTime) {
            return minimumPrice;
        }

        uint256 _priceDiff = (block.timestamp - startTime) * (startPrice - minimumPrice) / (endTime - startTime);
        return startPrice - _priceDiff;
    }

    function clearingPrice() public view returns (uint256) {
        /// @dev If auction successful, return tokenPrice
        uint256 _tokenPrice = tokenPrice();
        uint256 _currentPrice = priceFunction();
        return _tokenPrice > _currentPrice ? _tokenPrice : _currentPrice;
    }

    function priceDrop() public view returns (uint256) {
        uint256 _numerator = startPrice - minimumPrice;
        uint256 _denominator = endTime - startTime;
        return _numerator / _denominator;
    }

    function tokensClaimable(address _user) public view virtual returns (uint256 _claimerCommitment) {
        if (commitments[_user] == 0) {
            return 0;
        }
        _claimerCommitment = commitments[_user] * totalTokens / commitmentsTotal;
        _claimerCommitment -= claimed[_user];

        uint256 unclaimedTokens = IERC20(auctionToken).balanceOf(address(this));
        if (_claimerCommitment > unclaimedTokens) {
            _claimerCommitment = unclaimedTokens;
        }
    }

    function calculateCommitment(uint256 _commitment) public view returns (uint256) {
        uint256 _maxCommitment = uint256(totalTokens) * clearingPrice() / 1e18;
        if (commitmentsTotal + _commitment > _maxCommitment) {
            return _maxCommitment - commitmentsTotal;
        }
        return _commitment;
    }

    function remainCommitment() public view returns (uint256) {
        uint256 _maxCommitment = uint256(totalTokens) * clearingPrice() / 1e18;
        return _maxCommitment - commitmentsTotal;
    }

    function isOpen() public view returns (bool) {
        return block.timestamp >= startTime && block.timestamp <= endTime;
    }

    function auctionSuccessful() public view returns (bool) {
        return tokenPrice() >= clearingPrice();
    }

    function auctionEnded() public view returns (bool) {
        return auctionSuccessful() || block.timestamp > endTime;
    }

    function finalizeTimeExpired() public view returns (bool) {
        return endTime + 7 days < block.timestamp;
    }

    function totalTokensCommitted() public view returns (uint256) {
        return uint256(commitmentsTotal) * 1e18 / clearingPrice();
    }

    function hasAdminRole(address _sender) public view returns (bool) {
        return _sender == admin;
    }

    function commitTokens(address _from, uint256 _amount) public nonReentrant {
        uint256 _amountToTransfer = calculateCommitment(_amount);
        if (_amountToTransfer > 0) {
            IERC20(payToken).safeTransferFrom(msg.sender, address(this), _amountToTransfer);
            _addCommitment(_from, _amountToTransfer);
        }
    }

    function _addCommitment(address _addr, uint256 _commitment) internal {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "auction not live");
        require(!finalized, "auction finalized");
        commitments[_addr] += _commitment;
        commitmentsTotal += uint128(_commitment);
        emit AddedCommitment(_addr, _commitment);
    }

    function cancelAuction() public nonReentrant {
        require(hasAdminRole(msg.sender), "!admin");
        require(!finalized, "auction finalized");
        require(commitmentsTotal == 0, "auction completed");
        finalized = true;
        _finalizeFailedAuctionFund();
        emit AuctionCancelled();
    }

    function finalize() public nonReentrant {
        require(hasAdminRole(msg.sender) || finalizeTimeExpired(), "!admin");
        require(!finalized, "auction finalized");
        if (auctionSuccessful()) {
            emit AuctionSuccess(block.timestamp);
            _finalizeSuccessfulAuctionFund();
        } else {
            require(block.timestamp > endTime, "not finished");
            emit AuctionFailed(block.timestamp);
            _finalizeFailedAuctionFund();
        }
        finalized = true;
    }

    function transferAdmin(address _newAdmin) public {
        require(hasAdminRole(msg.sender), "!admin");
        require(_newAdmin != address(0), "address = 0");
        admin = _newAdmin;
        emit NewAdminSet(_newAdmin);
    }

    function withdrawTokens(address _to) public nonReentrant {
        if (auctionSuccessful()) {
            require(finalized, "Claim is not available until auction is closed");
            uint256 _claimableAmount = tokensClaimable(msg.sender);
            require(_claimableAmount > 0, "claimable = 0");
            claimed[msg.sender] = claimed[msg.sender] + _claimableAmount;
            _safeTransferToken(auctionToken, _to, _claimableAmount);
        } else {
            // Auction did not meet reserve price.
            // Return committed funds back to user.
            require(block.timestamp > endTime, "Claim is not available until auction is closed");
            uint256 fundsCommitted = commitments[msg.sender];
            commitments[msg.sender] = 0; // Stop multiple withdrawals and free some gas
            _safeTransferToken(payToken, _to, fundsCommitted);
        }
    }

    function withdraw(
        address _erc20,
        address _to,
        uint256 _val
    ) external returns (bool) {
        require(hasAdminRole(msg.sender), "!admin");
        IERC20(_erc20).safeTransfer(_to, _val);
        return true;
    }

    function withdrawETH(address payable recipient) external {
        require(hasAdminRole(msg.sender), "!admin");
        (bool success,) = recipient.call{value: address(this).balance}("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
    }

    function setAuctionTime(uint256 _startTime, uint256 _endTime) external {
        require(hasAdminRole(msg.sender), "!admin");
        require(_startTime < 10000000000, "unix timestamp in seconds");
        require(_endTime < 10000000000, "unix timestamp in seconds");
        require(_startTime >= block.timestamp, "start time < current time");
        require(_endTime > _startTime, "end time < start time");
        require(commitmentsTotal == 0, "auction started");

        startTime = uint64(_startTime);
        endTime = uint64(_endTime);

        emit AuctionTimeUpdated(_startTime, _endTime);
    }

    function setAuctionPrice(uint256 _startPrice, uint256 _minimumPrice) external {
        require(hasAdminRole(msg.sender), "!admin");
        require(_startPrice > _minimumPrice, "start price < minimum price");
        require(_minimumPrice != 0, "minimum price = 0");
        require(commitmentsTotal == 0, "auction started");

        startPrice = uint128(_startPrice);
        minimumPrice = uint128(_minimumPrice);

        emit AuctionPriceUpdated(_startPrice, _minimumPrice);
    }

    function setAuctionTreasury(address _treasury) external {
        require(hasAdminRole(msg.sender), "!admin");
        require(_treasury != address(0), "address = 0");
        auctionTreasury = _treasury;
        emit AuctionTreasuryUpdated(_treasury);
    }

    function _safeTransferToken(address _token, address _to, uint256 _amount) internal {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function _finalizeSuccessfulAuctionFund() internal virtual {
        _safeTransferToken(payToken, auctionTreasury, commitmentsTotal);
    }

    function _finalizeFailedAuctionFund() internal virtual {
        _safeTransferToken(auctionToken, auctionTreasury, totalTokens);
    }

    event AuctionDeployed(
        address indexed _auctionToken,
        address indexed _payToken,
        uint256 _totalTokens,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _startPrice,
        uint256 _minPrice,
        address _auctionAdmin,
        address _auctionTreasury
    );

    event AddedCommitment(address _addr, uint256 _commitment);

    event AuctionSuccess(uint256 _timeStamp);
    event AuctionFailed(uint256 _timeStamp);

    event AuctionCancelled();

    event NewAdminSet(address _admin);

    event AuctionTimeUpdated(uint256 _startTime, uint256 _endTime);
    event AuctionPriceUpdated(uint256 _startPrice, uint256 _minPrice);
    event AuctionTreasuryUpdated(address indexed _treasury);
}

contract EDEDutchAuction is DutchAuction {
    uint64 public constant MAX_VESTING_DURATION = 7 days;
    uint64 public vestingDuration;
    uint64 public vestingStart;

    constructor(
        address _auctionToken,
        address _payToken,
        uint128 _totalTokens,
        uint64 _startTime,
        uint64 _endTime,
        uint128 _startPrice,
        uint128 _minimumPrice,
        address _admin,
        address _treasury,
        uint64 _vestingDuration
    )
    DutchAuction(
    _auctionToken,
    _payToken,
    _totalTokens,
    _startTime,
    _endTime,
    _startPrice,
    _minimumPrice,
    _admin,
    _treasury
    )
    {
        require(_vestingDuration <= MAX_VESTING_DURATION, "> MAX_VESTING_DURATION");
        vestingDuration = _vestingDuration;
    }

    function tokensClaimableWithoutVesting(address _user) public view returns (uint256 _claimerCommitment) {
        if (commitments[_user] == 0) {
            return 0;
        }

        uint256 unclaimedTokens = IERC20(auctionToken).balanceOf(address(this));
        _claimerCommitment = commitments[_user] * totalTokens / commitmentsTotal;
        _claimerCommitment = _claimerCommitment - claimed[_user];
        if (_claimerCommitment > unclaimedTokens) {
            _claimerCommitment = unclaimedTokens;
        }
    }

    function tokensClaimable(address _user) public view override returns (uint256 _claimerCommitment) {
        if (vestingDuration == 0) {
            return tokensClaimableWithoutVesting(_user);
        }

        if (commitments[_user] == 0) {
            return 0;
        }

        if (vestingStart == 0) {
            return 0;
        }

        if (block.timestamp >= (vestingStart + vestingDuration)) {
            _claimerCommitment = commitments[_user] * totalTokens / commitmentsTotal;
        } else {
            uint256 _time = block.timestamp - vestingStart;
            _claimerCommitment = _time * commitments[_user] * totalTokens / commitmentsTotal / vestingDuration;
        }

        uint256 unclaimedTokens = IERC20(auctionToken).balanceOf(address(this));
        _claimerCommitment -= claimed[_user];
        if (_claimerCommitment > unclaimedTokens) {
            _claimerCommitment = unclaimedTokens;
        }
    }

    function _finalizeSuccessfulAuctionFund() internal override {
        _safeTransferToken(payToken, auctionTreasury, commitmentsTotal);
        if (vestingDuration > 0) {
            vestingStart = uint64(block.timestamp);
            emit VestingStarted(vestingStart);
        }
    }

    event VestingStarted(uint64 timestamp);
}

contract EDEAuctionFactory is Ownable {
    using SafeERC20 for IERC20;

    uint64 public  MIN_AUCTION_DURATION = 10 minutes;
    uint64 public  MAX_AUCTION_DURATION = 10 days;

    uint64 public vestingDuration;
    address public AuctionToken;
    address public payToken;
    address public treasury;
    address public admin;
    address[] public auctions;

    constructor(address _auctionToken, address _payToken, address _treasury, address _admin, uint64 _vestingDuration) {
        require(_auctionToken != address(0), "Invalid address");
        require(_payToken != address(0), "Invalid address");
        AuctionToken = _auctionToken;
        payToken = _payToken;
        setVestingDuration(_vestingDuration);
        setTreasury(_treasury);
        setAdmin(_admin);
        setVestingDuration(_vestingDuration);
    }

    function totalAuctions() public view returns (uint256) {
        return auctions.length;
    }

    function createAuction(
        uint128 _totalTokens,
        uint64 _startTime,
        uint64 _endTime,
        uint128 _startPrice,
        uint128 _minPrice
    ) external onlyOwner {
        require(_endTime - _startTime >= MIN_AUCTION_DURATION, "< MIN_AUCTION_DURATION");
        require(_endTime - _startTime <= MAX_AUCTION_DURATION, "> MAX_AUCTION_DURATION");

        EDEDutchAuction _newAuction = new EDEDutchAuction(
            AuctionToken,
            payToken,
            _totalTokens,
            _startTime,
            _endTime,
            _startPrice,
            _minPrice,
            admin,
            treasury,
            vestingDuration);

        IERC20(AuctionToken).safeTransferFrom(msg.sender, address(_newAuction), _totalTokens);

        auctions.push(address(_newAuction));

        emit AuctionCreated(address(_newAuction), AuctionToken, payToken, _totalTokens, _startTime, _endTime, _startPrice, _minPrice, admin, treasury);
    }

    function setTreasury(address _treasury) public onlyOwner {
        require(_treasury != address(0), "Invalid address");
        treasury = _treasury;
        emit AuctionTreasuryUpdated(_treasury);
    }

    function setAdmin(address _admin) public onlyOwner {
        require(_admin != address(0), "Invalid address");
        admin = _admin;
        emit AuctionAdminUpdated(_admin);
    }

    function setVestingDuration(uint64 _vestingDuration) public onlyOwner {
        vestingDuration = _vestingDuration;
        emit VestingDurationSet(_vestingDuration);
    }

    function setPayToken(address _payToken) public onlyOwner {
        require(_payToken != address(0), "Invalid address");
        payToken = _payToken;
    }

    function setAuctionToken(address _auctionToken) public onlyOwner {
        require(_auctionToken != address(0), "Invalid address");
        AuctionToken = _auctionToken;
    }

    function setMinAndMaxAuctionDuration(uint64 _minAuctionDuration, uint64 _maxAuctionDuration) public onlyOwner {
        require(_minAuctionDuration <= _maxAuctionDuration, "Invalid duration");
        MIN_AUCTION_DURATION = _minAuctionDuration;
        MAX_AUCTION_DURATION = _maxAuctionDuration;
    }

    event AuctionCreated(
        address indexed _auction,
        address indexed _auctionToken,
        address indexed _payToken,
        uint256 _totalTokens,
        uint64 _startTime,
        uint64 _endTime,
        uint256 _startPrice,
        uint256 _minPrice,
        address auctionAdmin,
        address auctionTreasury
    );
    event AuctionAdminUpdated(address indexed _address);
    event AuctionTreasuryUpdated(address indexed _address);
    event VestingDurationSet(uint64 _duration);
}
