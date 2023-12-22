// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./BitMaps.sol";

interface ERC20Detailed {
    function decimals() external view returns (uint8);
}

contract KercWLSale is Ownable {
    using BitMaps for BitMaps.BitMap;

    mapping(address => uint256) public balanceOf;
    BitMaps.BitMap private whitelist;
    BitMaps.BitMap private tokens;
    address[] public tokenList;
    address[] public participants;
    uint256 public constant minimumDeposit = 5_000;
    uint256 public constant hardCap = 2_500_000 ether;
    uint256 public immutable startTime;
    uint256 public endTime;
    uint256 public totalContributed;
    bool public isClosed;
    address public constant receiver =
        0xBeD86bad02560EdA4d71711c073B16524fA6816d;

    event Participate(address indexed user, address token, uint256 amount);
    event ContractStatus(uint256 at, bool closed);
    event EndTimeUpdated(uint256 endTime);
    event Whitelisted(address whitelistAddress);

    function _canParticipate(address _token, uint256 _amount) private view {
        require(open(), "ERR:NOT_OPEN");
        require(
            _isWhitelisted(msg.sender) || _amount >= minimumDeposit * 1e6,
            "ERR:NOT_WHITELISTED"
        );
        require(_amount > 0, "ERR:AMOUNT");
        require(tokens.get(uint160(_token)), "ERR:NOT_VALID_TOKEN");
        require(totalContributed + _amount <= hardCap, "ERR:AMT_TOO_BIG");
    }

    modifier canParticipate(address _token, uint256 _amount) {
        _canParticipate(_token, _amount);
        _;
    }

    constructor(uint256 _startTime, address[] memory _tokens) {
        uint256 numTokens = _tokens.length;
        require(numTokens > 0, "ERR:ZERO_TOKENS");

        for (uint256 i; i < numTokens; ++i) {
            ERC20Detailed(_tokens[i]).decimals(); // Sanity check
            tokens.set(uint160(_tokens[i]));
        }

        startTime = _startTime;
        endTime = startTime + 3600 * 24 * 3;
        tokenList = _tokens;
    }

    function open() public view returns (bool) {
        uint256 blockTime = block.timestamp;

        return
            !isClosed &&
            blockTime >= startTime &&
            blockTime <= endTime &&
            totalContributed < hardCap;
    }

    function participate(
        address _token,
        uint256 _amount
    ) external canParticipate(_token, _amount) {
        _participate(_token, _amount);
    }

    function participateWithPermit(
        address _token,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external canParticipate(_token, _amount) {
        SafeERC20.safePermit(
            IERC20Permit(_token),
            msg.sender,
            address(this),
            _amount,
            _deadline,
            _v,
            _r,
            _s
        );
        _participate(_token, _amount);
    }

    function _participate(address _token, uint256 _amount) private {
        address user = msg.sender;

        SafeERC20.safeTransferFrom(IERC20(_token), user, receiver, _amount);

        if (balanceOf[user] == 0) {
            participants.push(user);
        }

        unchecked {
            _amount *= 1e12; // Convert 1e6 to 1e18
            balanceOf[user] += _amount;
            totalContributed += _amount;
        }

        emit Participate(user, _token, _amount);
    }

    function numberOfParticipants() external view returns (uint256) {
        return participants.length;
    }

    function getTokens() external view returns (address[] memory) {
        return tokenList;
    }

    function _isWhitelisted(address _address) internal view returns (bool) {
        return whitelist.get(uint160(_address));
    }

    function isWhitelisted(address _address) external view returns (bool) {
        return _isWhitelisted(_address);
    }

    function currentTimestamp() external view returns (uint256) {
        return block.timestamp;
    }

    function setWhitelisted(
        address[] calldata _addresses,
        bool _whitelisted
    ) external onlyOwner {
        uint256 len = _addresses.length;
        for (uint256 i; i < len; ++i) {
            whitelist.setTo(uint160(_addresses[i]), _whitelisted);
            emit Whitelisted(_addresses[i]);
        }
    }

    function setClosed(bool _closed) external onlyOwner {
        if (isClosed != _closed) {
            isClosed = _closed;
            emit ContractStatus(block.timestamp, _closed);
        }
    }

    function setEndTime(uint256 _endTime) external onlyOwner {
        if (endTime != _endTime) {
            endTime = _endTime;
            emit EndTimeUpdated(_endTime);
        }
    }

    function withdrawETH() external onlyOwner {
        payable(receiver).transfer(address(this).balance);
    }

    function withdraw(IERC20 _token) external onlyOwner {
        _token.transfer(receiver, _token.balanceOf(address(this)));
    }
}

