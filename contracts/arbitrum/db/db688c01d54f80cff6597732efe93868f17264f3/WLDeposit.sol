// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18 <0.9.0;

import "./Ownable.sol";
import "./SafeERC20.sol";

// import "hardhat/console.sol";

interface ERC20Detailed {
    function decimals() external view returns (uint8);
}

contract KercWLDeposit is Ownable {
    mapping(address => uint8) public tokenDecimals;
    mapping(address => uint256) private tokenIndexes;
    address[] private tokens;
    address public receiver = 0xBeD86bad02560EdA4d71711c073B16524fA6816d;
    uint64 public depositAmount = 5000;
    bool public open;
    mapping(address => uint256) public balanceOf;
    address[] public participants;
    uint256 public totalContributed;

    event ContractStatus(uint256 at, bool open);
    event WhitelistObtained(address indexed user);
    event TokenUpdated(address token, bool enabled);
    event DepositAmountUpdated(uint256 amount);

    constructor(address[] memory _tokens) {
        open = true;
        enableTokens(_tokens);
    }

    function _canParticipate(address _token) private view {
        require(open, "ERR:NOT_OPEN");
        require(tokenDecimals[_token] > 0, "ERR:NOT_VALID_TOKEN");
        require(balanceOf[msg.sender] == 0, "ERR:ALREADY_DEPOSITED");
    }

    modifier canParticipate(address _token) {
        _canParticipate(_token);
        _;
    }

    function participate(address _token) external canParticipate(_token) {
        _participate(_token);
    }

    function participateWithPermit(
        address _token,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external canParticipate(_token) {
        SafeERC20.safePermit(
            IERC20Permit(_token),
            msg.sender,
            address(this),
            depositAmount * 10 ** tokenDecimals[_token],
            _deadline,
            _v,
            _r,
            _s
        );
        _participate(_token);
    }

    function _participate(address _token) private {
        uint256 amount = depositAmount * 10 ** tokenDecimals[_token];
        address user = msg.sender;

        SafeERC20.safeTransferFrom(IERC20(_token), user, receiver, amount);

        participants.push(user);

        amount = _convertToWei(_token, amount);
        unchecked {
            balanceOf[user] = amount;
            totalContributed += amount;
        }

        emit WhitelistObtained(user);
    }

    function _convertToWei(
        address _token,
        uint256 _amount
    ) private view returns (uint256) {
        uint8 decimals = tokenDecimals[_token];
        return decimals == 18 ? _amount : _amount * (10 ** (18 - decimals));
    }

    function numberOfParticipants() external view returns (uint256) {
        return participants.length;
    }

    function getTokens() external view returns (address[] memory) {
        return tokens;
    }

    function didParticipate(address _address) external view returns (bool) {
        return balanceOf[_address] > 0;
    }

    function setOpen(bool _open) external onlyOwner {
        if (open != _open) {
            open = _open;
            emit ContractStatus(block.timestamp, _open);
        }
    }

    function enableTokens(address[] memory _tokens) public onlyOwner {
        uint256 len = _tokens.length;
        for (uint256 i; i < len; ++i) {
            setToken(_tokens[i], true);
        }
    }

    function setToken(address _token, bool _enabled) public onlyOwner {
        if (_enabled && tokenDecimals[_token] == 0) {
            uint8 decimals = ERC20Detailed(_token).decimals();
            require(decimals > 0 && decimals <= 18, "ERR:DECIMALS");
            tokenDecimals[_token] = decimals;
            tokens.push(_token);
            tokenIndexes[_token] = tokens.length;
        } else if (!_enabled && tokenDecimals[_token] > 0) {
            tokens[tokenIndexes[_token] - 1] = tokens[tokens.length - 1];
            tokens.pop();
            tokenIndexes[_token] = 0;
            tokenDecimals[_token] = 0;
        } else {
            return;
        }

        emit TokenUpdated(_token, _enabled);
    }

    function setDepositAmount(uint64 _depositAmount) external onlyOwner {
        if (depositAmount != _depositAmount) {
            depositAmount = _depositAmount;

            emit DepositAmountUpdated(_depositAmount);
        }
    }

    function withdrawETH() external onlyOwner {
        payable(receiver).transfer(address(this).balance);
    }

    function withdraw(IERC20 _token) external onlyOwner {
        _token.transfer(receiver, _token.balanceOf(address(this)));
    }
}

