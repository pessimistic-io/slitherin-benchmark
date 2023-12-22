// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

import "./ITokenWallet.sol";

contract Readable {
    function since(uint _timestamp) internal view returns(uint) {
        if (not(passed(_timestamp))) {
            return 0;
        }
        return block.timestamp - _timestamp;
    }

    function passed(uint _timestamp) internal view returns(bool) {
        return _timestamp < block.timestamp;
    }

    function not(bool _condition) internal pure returns(bool) {
        return !_condition;
    }
}

contract UWUSale is Ownable, Readable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Address for address;

    ITokenWallet public UWUAsset;
    address payable public treasury;

    uint constant UWU = 10**18;
    uint constant public MIN_DEPOSIT = 857142857;
    uint constant public MAX_DEPOSIT = 0.000001 ether;
    uint constant public MAX_WHITELISTED_DEPOSIT = 0.0000007 ether;

    uint constant public SOFT_CAP = 0.0007 ether;
    uint constant public HARD_CAP = 0.0015 ether;
    uint constant public TOTAL_DISTRIBUTED = 1_750_000;

    struct State {
        uint totalDeposited;
        uint nextDepositId;
        uint clearedDepositId;
    }
    State private _state;
    mapping(uint => Deposit) public deposits;
    mapping(address => uint) public depositors;
    mapping(address => bool) public whitelisted;
    address[] public whitelistedArray;

    uint public SALE_START = 1681135200; // Monday, 10 April 2023, 2 PM UTC
    uint public SALE_END = SALE_START + 72 hours; // Thursday, 13 April 2023, 2 PM UTC

    struct Deposit {
        address payable user;
        uint amount;
        uint clearing1;
        uint clearing2;
        uint clearing3;
        uint clearing4;
    }

    event DepositEvent(address _from, uint _value);
    event ETHReturned(address _to, uint _amount);
    event Cleared();
    event ClearingPaused(uint _lastDepositId);
    event TreasurySet(address _treasury);
    event TokenWalletSet(address _tokenWallet);

    modifier onlyTreasury {
        require(msg.sender == treasury, 'Only treasury');
        _;
    }

    constructor(ITokenWallet _uwu, address payable _treasury) {
        UWUAsset = _uwu;
        treasury = _treasury;

        SALE_START = block.timestamp;
        SALE_END = SALE_START + 72 hours;
    }

    function whitelistLength() public view returns(uint) {
        return whitelistedArray.length;
    }

    function maximumDeposit() public view returns(uint) {
        bool isWhitelistRound = not(passed(SALE_START + 24 hours));
        uint maxValue = isWhitelistRound ? MAX_WHITELISTED_DEPOSIT : MAX_DEPOSIT;
        
        return maxValue;
    }

    function maximumDepositForAddress(address _user) public view returns(uint) {
        bool isWhitelistRound = not(passed(SALE_START + 24 hours));
        bool isWhitelisted = whitelisted[_user];
        uint maxValue = isWhitelistRound ? MAX_WHITELISTED_DEPOSIT : MAX_DEPOSIT;

        return isWhitelistRound && !isWhitelisted ? 0 : maxValue.sub(depositors[_user]);
    }

    function totalDeposited() public view returns(uint) {
        return _state.totalDeposited;
    }

    function nextDepositId() public view returns(uint) {
        return _state.nextDepositId;
    }

    function clearedDepositId() public view returns(uint) {
        return _state.clearedDepositId;
    }

    function setTreasury(address payable _treasury) public onlyOwner {
        require(_treasury != address(0), 'Zero address not allowed');
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    function setTokenWallet(ITokenWallet _uwu) external onlyOwner {
        require(address(_uwu) != address(0), 'Zero address not allowed');
        UWUAsset = _uwu;
        emit TokenWalletSet(address(_uwu));
    }

    function saleStarted() public view returns(bool) {
        return passed(SALE_START);
    }

    function saleEnded() public view returns(bool) {
        return passed(SALE_END) || _isTokensSold(totalDeposited());
    }

    function _saleEnded(uint _totalDeposited) private view returns(bool) {
        return passed(SALE_END) || _isTokensSold(_totalDeposited);
    }

    function ETHToUWU(uint _value) public view returns(uint) {
        return _ETHToUWU(_value, getSalePrice());
    }

    function UWUToETH(uint _value) public view returns(uint) {
        return _UWUToETH(_value, getSalePrice());
    }

    function _ETHToUWU(uint _value, uint _salePrice) private pure returns(uint) {
        return _value.div(_salePrice).mul(UWU);
    }

    function _UWUToETH(uint _value, uint _salePrice) private pure returns(uint) {
        return _value.mul(_salePrice).div(UWU);
    }

    function getSalePrice() public view returns(uint) {
        return _getSalePrice(totalDeposited());
    }

    function _getSalePrice(uint _totalDeposited) private pure returns(uint) {
        return _totalDeposited >= HARD_CAP ? 857142857 : _totalDeposited.div(TOTAL_DISTRIBUTED);
    }

    function _isTokensSold(uint _totalDeposited) internal pure returns(bool) {
        if (_totalDeposited < HARD_CAP) {
            uint remaining = HARD_CAP.sub(_totalDeposited);
            return remaining < MIN_DEPOSIT;
        }

        return true;
    }

    function addWhitelisted(address _whitelisted) external onlyOwner {
        whitelisted[_whitelisted] = true;
        whitelistedArray.push(_whitelisted);
    }

    function addWhitelistedArray(address[] memory _whitelistedArray) external onlyOwner {
        for (uint256 i = 0; i < _whitelistedArray.length; i++) {
            whitelisted[_whitelistedArray[i]] = true;
            whitelistedArray.push(_whitelistedArray[i]);
        }
    }

    function removeWhitelisted(address _whitelisted) external onlyOwner {
        delete whitelisted[_whitelisted];
    }

    receive() external payable {
        if (msg.sender == treasury) {
            return;
        }
        _deposit();
    }

    function depositETH() public payable {
        _deposit();
    }

    function _deposit() internal nonReentrant {
        State memory state = _state;
        treasury.transfer(msg.value);
        uint depositedValue = msg.value;
        bool isWhitelistRound = not(passed(SALE_START + 24 hours));
        uint maxValue = isWhitelistRound ? MAX_WHITELISTED_DEPOSIT : MAX_DEPOSIT;

        require(saleStarted(), 'Public sale not started yet');
        require(not(_saleEnded(state.totalDeposited)), 'Public sale already ended');
        require(passed(SALE_START + 24 hours) || whitelisted[msg.sender], 'You are not whitelisted');
        require(depositedValue >= MIN_DEPOSIT, 'Minimum deposit not met');
        require(depositors[msg.sender].add(depositedValue) <= maxValue, 'Maximum deposit reached');

        deposits[state.nextDepositId] = Deposit(payable(msg.sender), depositedValue, 1, 1, 1, 1);
        depositors[msg.sender] = depositors[msg.sender].add(depositedValue);
        state.nextDepositId = state.nextDepositId.add(1);

        state.totalDeposited = state.totalDeposited.add(depositedValue);
        _state = state;

        emit DepositEvent(msg.sender, depositedValue);
    }

    function clearing() public onlyOwner nonReentrant {
        State memory state = _state;
        require(_saleEnded(state.totalDeposited), 'Public sale not ended yet');
        require(state.nextDepositId > state.clearedDepositId, 'Clearing finished');
        uint salePrice = _getSalePrice(state.totalDeposited);
        ITokenWallet uwuAsset = UWUAsset;

        uint lockedBalance = uwuAsset.available();
        for (uint i = state.clearedDepositId; i < state.nextDepositId; i++) {
            if (gasleft() < 500000) {
                state.clearedDepositId = i;
                _state = state;
                emit ClearingPaused(i);
                return;
            }
            Deposit memory deposit = deposits[i];
            delete deposits[i];

            uint uwu = _ETHToUWU(deposit.amount, salePrice);
            bool isSuccessfulSale = state.totalDeposited >= SOFT_CAP;
            if (isSuccessfulSale && lockedBalance >= uwu) {
                uwuAsset.safeTransfer(deposit.user, uwu);
                lockedBalance = lockedBalance.sub(uwu);
            } else if (isSuccessfulSale && lockedBalance > 0) {
                uwuAsset.safeTransfer(deposit.user, lockedBalance);
                uint tokensLeftToETH = uwu.sub(lockedBalance);
                uint ethAmount = _UWUToETH(tokensLeftToETH, salePrice);
                lockedBalance = 0;
                deposit.user.transfer(ethAmount);
                emit ETHReturned(deposit.user, ethAmount);
            } else {
                deposit.user.transfer(deposit.amount);
                emit ETHReturned(deposit.user, deposit.amount);
            }
        }
        state.clearedDepositId = state.nextDepositId;

        _state = state;
        emit Cleared();
    }

    function recoverTokens(IERC20 _token, address _to, uint _value) public onlyTreasury {
        _token.safeTransfer(_to, _value);
    }

    function recoverETH() public onlyTreasury {
        treasury.transfer(address(this).balance);
    }
}

